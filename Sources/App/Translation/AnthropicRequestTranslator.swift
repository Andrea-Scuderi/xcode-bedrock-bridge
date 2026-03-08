import SotoCore
import SotoBedrockRuntime

struct AnthropicRequestTranslator: Sendable {

    func translate(request: AnthropicRequest, resolvedModelID: String, modelMapper: ModelMapper) throws -> (
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) {
        let hasImages = request.messages.contains { msg in
            msg.content.blocks.contains { block in
                block.type == "image" && block.source != nil
            }
        }
        if hasImages && !modelMapper.supportsImageInput(bedrockID: resolvedModelID) {
            throw ImageTranslationError.unsupportedModel(resolvedModelID)
        }

        let system = request.system.map { [BedrockRuntime.SystemContentBlock.text($0.plainText)] } ?? []
        let messages = try request.messages.compactMap { try translateMessage($0) }
        let inferenceConfig = BedrockRuntime.InferenceConfiguration(
            maxTokens: request.maxTokens,
            temperature: request.temperature.map { Float($0) },
            topP: request.topP.map { Float($0) }
        )
        let toolConfig = translateToolConfig(tools: request.tools, toolChoice: request.toolChoice)
        return (system, messages, inferenceConfig, toolConfig)
    }

    // MARK: - Messages

    private func translateMessage(_ msg: AnthropicMessage) throws -> BedrockRuntime.Message? {
        let role: BedrockRuntime.ConversationRole
        switch msg.role {
        case "user":      role = .user
        case "assistant": role = .assistant
        default:          return nil
        }
        let content = try msg.content.blocks.compactMap { try translateBlock($0) }
        guard !content.isEmpty else { return nil }
        return BedrockRuntime.Message(content: content, role: role)
    }

    private func translateBlock(_ block: AnthropicContentBlock) throws -> BedrockRuntime.ContentBlock? {
        switch block.type {
        case "text":
            guard let text = block.text else { return nil }
            return .text(text)

        case "tool_use":
            guard let id = block.id, let name = block.name else { return nil }
            let input = block.input?.toAWSDocument() ?? .map([:])
            return .toolUse(BedrockRuntime.ToolUseBlock(input: input, name: name, toolUseId: id))

        case "tool_result":
            guard let toolUseId = block.toolUseId else { return nil }
            let resultContent: [BedrockRuntime.ToolResultContentBlock]
            if let c = block.content {
                resultContent = [.text(c.asText)]
            } else {
                resultContent = []
            }
            return .toolResult(BedrockRuntime.ToolResultBlock(content: resultContent, toolUseId: toolUseId))

        case "image":
            guard let source = block.source else { return nil }
            return try translateImageSource(source)

        default:
            return nil
        }
    }

    private func translateImageSource(_ source: AnthropicImageSource) throws -> BedrockRuntime.ContentBlock {
        guard source.mediaType.hasPrefix("image/") else {
            throw ImageTranslationError.unsupportedFormat(source.mediaType)
        }
        let format = String(source.mediaType.dropFirst(6))  // drop "image/"
        let allowedFormats = ["jpeg", "png", "gif", "webp"]
        guard allowedFormats.contains(format),
              let imageFormat = BedrockRuntime.ImageFormat(rawValue: format) else {
            throw ImageTranslationError.unsupportedFormat(format)
        }
        let estimatedBytes = (source.data.count * 3) / 4
        guard estimatedBytes <= 3_932_160 else {
            throw ImageTranslationError.imageTooLarge(estimatedBytes)
        }
        let imageSource = BedrockRuntime.ImageSource.bytes(AWSBase64Data.base64(source.data))
        return .image(BedrockRuntime.ImageBlock(format: imageFormat, source: imageSource))
    }

    // MARK: - Tools

    private func translateToolConfig(
        tools: [AnthropicTool]?,
        toolChoice: AnthropicToolChoice?
    ) -> BedrockRuntime.ToolConfiguration? {
        guard let tools, !tools.isEmpty else { return nil }

        let bedrockTools: [BedrockRuntime.Tool] = tools.map { tool in
            let schema = BedrockRuntime.ToolInputSchema(json: tool.inputSchema.toAWSDocument())
            let spec = BedrockRuntime.ToolSpecification(
                description: tool.description,
                inputSchema: schema,
                name: tool.name
            )
            return .toolSpec(spec)
        }

        let bedrockChoice = toolChoice.flatMap { translateToolChoice($0) }
        return BedrockRuntime.ToolConfiguration(toolChoice: bedrockChoice, tools: bedrockTools)
    }

    private func translateToolChoice(_ choice: AnthropicToolChoice) -> BedrockRuntime.ToolChoice? {
        switch choice.type {
        case "auto":               return .auto(BedrockRuntime.AutoToolChoice())
        case "any":                return .any(BedrockRuntime.AnyToolChoice())
        case "tool":
            guard let name = choice.name else { return .auto(BedrockRuntime.AutoToolChoice()) }
            return .tool(BedrockRuntime.SpecificToolChoice(name: name))
        case "none":               return nil  // Bedrock has no "none"; omit toolConfig instead
        default:                   return .auto(BedrockRuntime.AutoToolChoice())
        }
    }
}
