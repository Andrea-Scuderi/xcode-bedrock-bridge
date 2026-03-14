import Vapor
import SotoCore
import SotoBedrockRuntime

struct RequestTranslator: Sendable {

    /// Translate OpenAI chat messages into Bedrock Converse API inputs.
    /// Returns (systemPrompts, conversationMessages, inferenceConfig, toolConfig).
    /// Throws `ImageTranslationError` when images are present but the model
    /// does not support vision input, or when an image is invalid or too large.
    func translate(
        request: ChatCompletionRequest,
        modelID: String,
        modelMapper: ModelMapper
    ) throws -> (
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) {
        var systemBlocks: [BedrockRuntime.SystemContentBlock] = []
        var conversationMessages: [ChatMessage] = []

        for message in request.messages {
            if message.role == "system" {
                systemBlocks.append(.text(message.content.textOnly))
            } else {
                conversationMessages.append(message)
            }
        }

        let hasImages = conversationMessages.contains { $0.content.hasImages }
        if hasImages && !modelMapper.supportsImageInput(bedrockID: modelID) {
            throw ImageTranslationError.unsupportedModel(modelID)
        }

        let bedrockMessages = try consolidateMessages(conversationMessages)

        let inferenceConfig = BedrockRuntime.InferenceConfiguration(
            maxTokens: request.maxTokens ?? 4096,
            stopSequences: request.stop,
            temperature: request.temperature.map { Float($0) },
            topP: request.topP.map { Float($0) }
        )

        let toolConfig = translateToolConfig(tools: request.tools, toolChoice: request.toolChoice)

        return (systemBlocks, bedrockMessages, inferenceConfig, toolConfig)
    }

    // MARK: - Tool Configuration

    private func translateToolConfig(
        tools: [JSONValue]?,
        toolChoice: JSONValue?
    ) -> BedrockRuntime.ToolConfiguration? {
        guard let tools, !tools.isEmpty else { return nil }

        // "none" means don't forward tools at all
        if case .string(let s) = toolChoice, s == "none" { return nil }

        let bedrockTools: [BedrockRuntime.Tool] = tools.compactMap { tool in
            guard case .object(let obj) = tool,
                  case .object(let fn) = obj["function"],
                  case .string(let name) = fn["name"] else { return nil }
            let description: String?
            if case .string(let d) = fn["description"] { description = d } else { description = nil }
            let schema: BedrockRuntime.ToolInputSchema
            if let params = fn["parameters"] {
                schema = BedrockRuntime.ToolInputSchema(json: params.toAWSDocument())
            } else {
                schema = BedrockRuntime.ToolInputSchema(json: .map([:]))
            }
            let spec = BedrockRuntime.ToolSpecification(description: description, inputSchema: schema, name: name)
            return .toolSpec(spec)
        }

        guard !bedrockTools.isEmpty else { return nil }
        let bedrockChoice = toolChoice.flatMap { translateToolChoice($0) }
        return BedrockRuntime.ToolConfiguration(toolChoice: bedrockChoice, tools: bedrockTools)
    }

    private func translateToolChoice(_ choice: JSONValue) -> BedrockRuntime.ToolChoice? {
        switch choice {
        case .string(let s):
            switch s {
            case "required": return .any(BedrockRuntime.AnyToolChoice())
            case "none":     return nil
            default:         return .auto(BedrockRuntime.AutoToolChoice())  // "auto"
            }
        case .object(let obj):
            if case .object(let fn) = obj["function"], case .string(let name) = fn["name"] {
                return .tool(BedrockRuntime.SpecificToolChoice(name: name))
            }
            return .auto(BedrockRuntime.AutoToolChoice())
        default:
            return .auto(BedrockRuntime.AutoToolChoice())
        }
    }

    // MARK: - Message Consolidation

    /// Bedrock requires strict user/assistant alternation.
    /// Converts each ChatMessage to (bedrockRole, contentBlocks) then merges consecutive same-role groups.
    private func consolidateMessages(_ messages: [ChatMessage]) throws -> [BedrockRuntime.Message] {
        // Phase 1: convert each message to (role, contentBlocks)
        var pairs: [(role: BedrockRuntime.ConversationRole, blocks: [BedrockRuntime.ContentBlock])] = []

        for message in messages {
            switch message.role {
            case "user":
                let blocks = try makeContentBlocks(from: message.content.asParts)
                guard !blocks.isEmpty else { continue }
                pairs.append((.user, blocks))

            case "assistant":
                var blocks: [BedrockRuntime.ContentBlock] = try makeContentBlocks(from: message.content.asParts)
                if let toolCalls = message.toolCalls {
                    for tc in toolCalls {
                        guard let id = tc.id, let name = tc.function.name else { continue }
                        let input = parseToolInput(tc.function.arguments ?? "")
                        blocks.append(.toolUse(BedrockRuntime.ToolUseBlock(input: input, name: name, toolUseId: id)))
                    }
                }
                guard !blocks.isEmpty else { continue }
                pairs.append((.assistant, blocks))

            case "tool":
                let toolCallId = message.toolCallId ?? ""
                let resultContent: [BedrockRuntime.ToolResultContentBlock] = [.text(message.content.textOnly)]
                let block: BedrockRuntime.ContentBlock = .toolResult(
                    BedrockRuntime.ToolResultBlock(content: resultContent, toolUseId: toolCallId)
                )
                pairs.append((.user, [block]))

            default:
                continue
            }
        }

        // Phase 2: merge consecutive same-role groups
        var groups: [(role: BedrockRuntime.ConversationRole, blocks: [BedrockRuntime.ContentBlock])] = []
        for pair in pairs {
            if let last = groups.last, last.role == pair.role {
                groups[groups.count - 1].blocks += pair.blocks
            } else {
                groups.append(pair)
            }
        }

        return groups.compactMap { group -> BedrockRuntime.Message? in
            guard !group.blocks.isEmpty else { return nil }
            return BedrockRuntime.Message(content: group.blocks, role: group.role)
        }
    }

    /// Convert MessagePart array to Bedrock ContentBlock array, buffering consecutive text.
    private func makeContentBlocks(from parts: [MessagePart]) throws -> [BedrockRuntime.ContentBlock] {
        var blocks: [BedrockRuntime.ContentBlock] = []
        var textBuffer = ""

        for part in parts {
            switch part {
            case .text(let t):
                textBuffer += t
            case .image(let img):
                if !textBuffer.isEmpty {
                    blocks.append(.text(textBuffer))
                    textBuffer = ""
                }
                blocks.append(try makeBedrockImageBlock(img))
            }
        }

        if !textBuffer.isEmpty {
            blocks.append(.text(textBuffer))
        }
        return blocks
    }

    private func makeBedrockImageBlock(_ img: ImageData) throws -> BedrockRuntime.ContentBlock {
        let allowedFormats = ["jpeg", "png", "gif", "webp"]
        guard allowedFormats.contains(img.format),
              let format = BedrockRuntime.ImageFormat(rawValue: img.format) else {
            throw ImageTranslationError.unsupportedFormat(img.format)
        }
        let estimatedBytes = (img.base64Data.count * 3) / 4
        guard estimatedBytes <= 3_932_160 else {
            throw ImageTranslationError.imageTooLarge(estimatedBytes)
        }
        let imageSource = BedrockRuntime.ImageSource.bytes(AWSBase64Data.base64(img.base64Data))
        return .image(BedrockRuntime.ImageBlock(format: format, source: imageSource))
    }

    /// Parse a JSON string into an AWSDocument for Bedrock tool input.
    private func parseToolInput(_ arguments: String) -> AWSDocument {
        guard let data = arguments.data(using: .utf8),
              let jsonValue = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return .map([:])
        }
        return jsonValue.toAWSDocument()
    }
}
