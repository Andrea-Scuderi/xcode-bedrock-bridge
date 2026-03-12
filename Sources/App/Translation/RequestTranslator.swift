import SotoCore
import SotoBedrockRuntime

struct RequestTranslator: Sendable {

    /// Translate OpenAI chat messages into Bedrock Converse API inputs.
    /// Returns (systemPrompts, conversationMessages, inferenceConfig).
    /// Throws `ImageTranslationError` when images are present but the model
    /// does not support vision input, or when an image is invalid or too large.
    func translate(
        request: ChatCompletionRequest,
        modelID: String,
        modelMapper: ModelMapper
    ) throws -> (
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration
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
            temperature: request.temperature.map { Float($0) },
            topP: request.topP.map { Float($0) }
        )

        return (systemBlocks, bedrockMessages, inferenceConfig)
    }

    /// Bedrock requires strict user/assistant alternation.
    /// Merge consecutive messages with the same role, preserving image parts.
    private func consolidateMessages(_ messages: [ChatMessage]) throws -> [BedrockRuntime.Message] {
        // Group consecutive same-role messages, merging their parts.
        var groups: [(role: String, parts: [MessagePart])] = []
        for message in messages {
            if let last = groups.last, last.role == message.role {
                groups[groups.count - 1].parts += [.text("\n")] + message.content.asParts
            } else {
                groups.append((role: message.role, parts: message.content.asParts))
            }
        }

        return try groups.compactMap { group -> BedrockRuntime.Message? in
            let role: BedrockRuntime.ConversationRole
            switch group.role {
            case "user":      role = .user
            case "assistant": role = .assistant
            default:          return nil
            }

            var contentBlocks: [BedrockRuntime.ContentBlock] = []
            var textBuffer = ""

            for part in group.parts {
                switch part {
                case .text(let t):
                    textBuffer += t
                case .image(let img):
                    if !textBuffer.isEmpty {
                        contentBlocks.append(.text(textBuffer))
                        textBuffer = ""
                    }
                    contentBlocks.append(try makeBedrockImageBlock(img))
                }
            }

            if !textBuffer.isEmpty {
                contentBlocks.append(.text(textBuffer))
            }

            guard !contentBlocks.isEmpty else { return nil }
            return BedrockRuntime.Message(content: contentBlocks, role: role)
        }
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
}
