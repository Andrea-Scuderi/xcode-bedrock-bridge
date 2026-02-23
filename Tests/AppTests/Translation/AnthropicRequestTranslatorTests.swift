import Testing
import SotoBedrockRuntime
@testable import App

@Suite("AnthropicRequestTranslator")
struct AnthropicRequestTranslatorTests {

    let translator = AnthropicRequestTranslator()

    private func makeRequest(
        system: AnthropicSystem? = nil,
        messages: [AnthropicMessage],
        tools: [AnthropicTool]? = nil,
        toolChoice: AnthropicToolChoice? = nil,
        maxTokens: Int = 1024,
        temperature: Double? = nil,
        topP: Double? = nil
    ) -> AnthropicRequest {
        AnthropicRequest(
            model: "claude-sonnet",
            messages: messages,
            maxTokens: maxTokens,
            system: system,
            tools: tools,
            toolChoice: toolChoice,
            stream: nil,
            temperature: temperature,
            topP: topP,
            stopSequences: nil
        )
    }

    @Test("plain text system prompt extracted as one SystemContentBlock")
    func plainTextSystemPromptExtracted() {
        let request = makeRequest(
            system: .text("Be helpful"),
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (system, _, _, _) = translator.translate(request: request)
        #expect(system.count == 1)
    }

    @Test("multi-block system prompt joined into one block")
    func blocksSystemPromptJoined() {
        let request = makeRequest(
            system: .blocks([
                AnthropicTextBlock(type: "text", text: "Block one"),
                AnthropicTextBlock(type: "text", text: "Block two"),
            ]),
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (system, _, _, _) = translator.translate(request: request)
        #expect(system.count == 1)
        switch system[0] {
        case .text(let t):
            #expect(t.contains("Block one"))
            #expect(t.contains("Block two"))
        default:
            Issue.record("Expected .text system block")
        }
    }

    @Test("nil system produces empty array")
    func nilSystemProducesEmptyArray() {
        let request = makeRequest(
            system: nil,
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (system, _, _, _) = translator.translate(request: request)
        #expect(system.isEmpty)
    }

    @Test("text content block translates to .text content block")
    func textContentBlockTranslated() {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([
                AnthropicContentBlock.text("Hello")
            ]))]
        )
        let (_, messages, _, _) = translator.translate(request: request)
        #expect(messages.count == 1)
        #expect(messages.first?.content.count == 1)
    }

    @Test("tool_use block translates to .toolUse content block")
    func toolUseBlockTranslated() {
        let block = AnthropicContentBlock(
            type: "tool_use",
            text: nil,
            id: "tool-123",
            name: "my_tool",
            input: .object(["arg": .string("value")]),
            toolUseId: nil,
            content: nil
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let (_, messages, _, _) = translator.translate(request: request)
        #expect(messages.count == 1)
        guard let contentBlock = messages.first?.content.first else {
            Issue.record("Expected content block")
            return
        }
        switch contentBlock {
        case .toolUse(let tu):
            #expect(tu.name == "my_tool")
            #expect(tu.toolUseId == "tool-123")
        default:
            Issue.record("Expected .toolUse content block")
        }
    }

    @Test("tool_result block translates to .toolResult content block")
    func toolResultBlockTranslated() {
        let block = AnthropicContentBlock(
            type: "tool_result",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: "tool-123",
            content: .text("the result")
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let (_, messages, _, _) = translator.translate(request: request)
        #expect(messages.count == 1)
        guard let contentBlock = messages.first?.content.first else {
            Issue.record("Expected content block")
            return
        }
        switch contentBlock {
        case .toolResult(let tr):
            #expect(tr.toolUseId == "tool-123")
        default:
            Issue.record("Expected .toolResult content block")
        }
    }

    @Test("unknown content block type is dropped")
    func unknownContentBlockDropped() {
        let block = AnthropicContentBlock(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let (_, messages, _, _) = translator.translate(request: request)
        // Message with no valid content blocks is dropped entirely
        #expect(messages.isEmpty)
    }

    @Test("tool choice 'auto' translates to .auto")
    func toolChoiceAutoTranslated() {
        let tool = AnthropicTool(name: "my_tool", description: nil, inputSchema: .object([:]))
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: [tool],
            toolChoice: AnthropicToolChoice(type: "auto", name: nil)
        )
        let (_, _, _, toolConfig) = translator.translate(request: request)
        guard let tc = toolConfig else {
            Issue.record("Expected non-nil toolConfig")
            return
        }
        guard let choice = tc.toolChoice else {
            Issue.record("Expected non-nil toolChoice")
            return
        }
        switch choice {
        case .auto:
            break
        default:
            Issue.record("Expected .auto tool choice, got \(choice)")
        }
    }

    @Test("tool choice 'any' translates to .any")
    func toolChoiceAnyTranslated() {
        let tool = AnthropicTool(name: "my_tool", description: nil, inputSchema: .object([:]))
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: [tool],
            toolChoice: AnthropicToolChoice(type: "any", name: nil)
        )
        let (_, _, _, toolConfig) = translator.translate(request: request)
        guard let tc = toolConfig else {
            Issue.record("Expected non-nil toolConfig")
            return
        }
        guard let choice = tc.toolChoice else {
            Issue.record("Expected non-nil toolChoice")
            return
        }
        switch choice {
        case .any:
            break
        default:
            Issue.record("Expected .any tool choice, got \(choice)")
        }
    }

    @Test("tool choice 'tool' translates to .tool with name")
    func toolChoiceSpecificToolTranslated() {
        let tool = AnthropicTool(name: "my_tool", description: nil, inputSchema: .object([:]))
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: [tool],
            toolChoice: AnthropicToolChoice(type: "tool", name: "my_tool")
        )
        let (_, _, _, toolConfig) = translator.translate(request: request)
        guard let tc = toolConfig else {
            Issue.record("Expected non-nil toolConfig")
            return
        }
        guard let choice = tc.toolChoice else {
            Issue.record("Expected non-nil toolChoice")
            return
        }
        switch choice {
        case .tool(let specific):
            #expect(specific.name == "my_tool")
        default:
            Issue.record("Expected .tool choice with name, got \(choice)")
        }
    }

    @Test("tool choice 'none' with no tools produces nil toolConfig")
    func toolChoiceNoneProducesNilToolConfig() {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: nil,
            toolChoice: AnthropicToolChoice(type: "none", name: nil)
        )
        let (_, _, _, toolConfig) = translator.translate(request: request)
        #expect(toolConfig == nil)
    }

    @Test("inference config set correctly from request fields")
    func inferenceConfigFromAnthropicRequest() {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            maxTokens: 512,
            temperature: 0.8,
            topP: 0.95
        )
        let (_, _, inferenceConfig, _) = translator.translate(request: request)
        #expect(inferenceConfig.maxTokens == 512)
        #expect(abs((inferenceConfig.temperature ?? 0) - Float(0.8)) < Float(0.001))
        #expect(abs((inferenceConfig.topP ?? 0) - Float(0.95)) < Float(0.001))
    }
}
