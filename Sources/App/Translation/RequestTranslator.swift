import SotoBedrockRuntime

struct RequestTranslator: Sendable {

    /// Translate OpenAI chat messages into Bedrock Converse API inputs.
    /// Returns (systemPrompts, conversationMessages, inferenceConfig)
    func translate(
        request: ChatCompletionRequest,
        modelID: String
    ) -> (
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration
    ) {
        var systemBlocks: [BedrockRuntime.SystemContentBlock] = []
        var conversationMessages: [ChatMessage] = []

        for message in request.messages {
            if message.role == "system" {
                systemBlocks.append(.text(message.content))
            } else {
                conversationMessages.append(message)
            }
        }

        let bedrockMessages = consolidateMessages(conversationMessages)

        let inferenceConfig = BedrockRuntime.InferenceConfiguration(
            maxTokens: request.maxTokens ?? 4096,
            temperature: request.temperature.map { Float($0) },
            topP: request.topP.map { Float($0) }
        )

        return (systemBlocks, bedrockMessages, inferenceConfig)
    }

    /// Bedrock requires strict user/assistant alternation.
    /// Merge consecutive messages with the same role.
    private func consolidateMessages(_ messages: [ChatMessage]) -> [BedrockRuntime.Message] {
        var consolidated: [ChatMessage] = []

        for message in messages {
            if let last = consolidated.last, last.role == message.role {
                // Merge content with a newline
                consolidated[consolidated.count - 1] = ChatMessage(
                    role: last.role,
                    content: last.content + "\n" + message.content
                )
            } else {
                consolidated.append(message)
            }
        }

        return consolidated.compactMap { message -> BedrockRuntime.Message? in
            let role: BedrockRuntime.ConversationRole
            switch message.role {
            case "user":      role = .user
            case "assistant": role = .assistant
            default:          return nil
            }

            let contentBlock = BedrockRuntime.ContentBlock.text(message.content)
            return BedrockRuntime.Message(content: [contentBlock], role: role)
        }
    }
}
