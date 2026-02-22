import SotoCore
import SotoBedrockRuntime

struct AnthropicRequestTranslator: Sendable {

    func translate(request: AnthropicRequest) -> (
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) {
        let system = request.system.map { [BedrockRuntime.SystemContentBlock.text($0.plainText)] } ?? []
        let messages = request.messages.compactMap { translateMessage($0) }
        let inferenceConfig = BedrockRuntime.InferenceConfiguration(
            maxTokens: request.maxTokens,
            temperature: request.temperature.map { Float($0) },
            topP: request.topP.map { Float($0) }
        )
        let toolConfig = translateToolConfig(tools: request.tools, toolChoice: request.toolChoice)
        return (system, messages, inferenceConfig, toolConfig)
    }

    // MARK: - Messages

    private func translateMessage(_ msg: AnthropicMessage) -> BedrockRuntime.Message? {
        let role: BedrockRuntime.ConversationRole
        switch msg.role {
        case "user":      role = .user
        case "assistant": role = .assistant
        default:          return nil
        }
        let content = msg.content.blocks.compactMap { translateBlock($0) }
        guard !content.isEmpty else { return nil }
        return BedrockRuntime.Message(content: content, role: role)
    }

    private func translateBlock(_ block: AnthropicContentBlock) -> BedrockRuntime.ContentBlock? {
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

        default:
            return nil
        }
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
