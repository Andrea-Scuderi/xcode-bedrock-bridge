import Testing
import SotoBedrockRuntime
@testable import App

@Suite("AnthropicRequestTranslator")
struct AnthropicRequestTranslatorTests {

    let translator = AnthropicRequestTranslator()
    let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")

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
    func plainTextSystemPromptExtracted() throws {
        let request = makeRequest(
            system: .text("Be helpful"),
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (system, _, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(system.count == 1)
    }

    @Test("multi-block system prompt joined into one block")
    func blocksSystemPromptJoined() throws {
        let request = makeRequest(
            system: .blocks([
                AnthropicTextBlock(type: "text", text: "Block one"),
                AnthropicTextBlock(type: "text", text: "Block two"),
            ]),
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (system, _, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
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
    func nilSystemProducesEmptyArray() throws {
        let request = makeRequest(
            system: nil,
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (system, _, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(system.isEmpty)
    }

    @Test("text content block translates to .text content block")
    func textContentBlockTranslated() throws {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([
                AnthropicContentBlock.text("Hello")
            ]))]
        )
        let (_, messages, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(messages.count == 1)
        #expect(messages.first?.content.count == 1)
    }

    @Test("tool_use block translates to .toolUse content block")
    func toolUseBlockTranslated() throws {
        let block = AnthropicContentBlock(
            type: "tool_use",
            text: nil,
            id: "tool-123",
            name: "my_tool",
            input: .object(["arg": .string("value")]),
            toolUseId: nil,
            content: nil,
            source: nil
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let (_, messages, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
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
    func toolResultBlockTranslated() throws {
        let block = AnthropicContentBlock(
            type: "tool_result",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: "tool-123",
            content: .text("the result"),
            source: nil
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let (_, messages, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
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

    @Test("image block with nil source is dropped")
    func unknownContentBlockDropped() throws {
        let block = AnthropicContentBlock(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            source: nil
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let (_, messages, _, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        // Message with no valid content blocks is dropped entirely
        #expect(messages.isEmpty)
    }

    @Test("tool choice 'auto' translates to .auto")
    func toolChoiceAutoTranslated() throws {
        let tool = AnthropicTool(name: "my_tool", description: nil, inputSchema: .object([:]))
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: [tool],
            toolChoice: AnthropicToolChoice(type: "auto", name: nil)
        )
        let (_, _, _, toolConfig) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
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
    func toolChoiceAnyTranslated() throws {
        let tool = AnthropicTool(name: "my_tool", description: nil, inputSchema: .object([:]))
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: [tool],
            toolChoice: AnthropicToolChoice(type: "any", name: nil)
        )
        let (_, _, _, toolConfig) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
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
    func toolChoiceSpecificToolTranslated() throws {
        let tool = AnthropicTool(name: "my_tool", description: nil, inputSchema: .object([:]))
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: [tool],
            toolChoice: AnthropicToolChoice(type: "tool", name: "my_tool")
        )
        let (_, _, _, toolConfig) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
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
    func toolChoiceNoneProducesNilToolConfig() throws {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            tools: nil,
            toolChoice: AnthropicToolChoice(type: "none", name: nil)
        )
        let (_, _, _, toolConfig) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(toolConfig == nil)
    }

    @Test("inference config set correctly from request fields")
    func inferenceConfigFromAnthropicRequest() throws {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            maxTokens: 512,
            temperature: 0.8,
            topP: 0.95
        )
        let (_, _, inferenceConfig, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(inferenceConfig.maxTokens == 512)
        #expect(abs((inferenceConfig.temperature ?? 0) - Float(0.8)) < Float(0.001))
        #expect(abs((inferenceConfig.topP ?? 0) - Float(0.95)) < Float(0.001))
    }

    @Test("stopSequences forwarded to inferenceConfig")
    func stopSequencesForwardedToInferenceConfig() throws {
        let request = AnthropicRequest(
            model: "claude-sonnet",
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))],
            maxTokens: 1024,
            system: nil,
            tools: nil,
            toolChoice: nil,
            stream: nil,
            temperature: nil,
            topP: nil,
            stopSequences: ["</answer>", "\n\nHuman:"]
        )
        let (_, _, inferenceConfig, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(inferenceConfig.stopSequences == ["</answer>", "\n\nHuman:"])
    }

    @Test("nil stopSequences produces nil in inferenceConfig")
    func nilStopSequencesProducesNilInInferenceConfig() throws {
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .text("Hi"))]
        )
        let (_, _, inferenceConfig, _) = try translator.translate(request: request, resolvedModelID: "some-model", modelMapper: mapper)
        #expect(inferenceConfig.stopSequences == nil)
    }

    // MARK: - Image Support

    @Test("image block with valid source translates to .image content block")
    func imageBlockWithValidSourceTranslated() throws {
        let source = AnthropicImageSource(
            type: "base64",
            mediaType: "image/png",
            data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        )
        let block = AnthropicContentBlock(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            source: source
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let modelID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        let (_, messages, _, _) = try translator.translate(request: request, resolvedModelID: modelID, modelMapper: mapper)
        #expect(messages.count == 1)
        guard let contentBlock = messages.first?.content.first else {
            Issue.record("Expected content block")
            return
        }
        if case .image = contentBlock { } else {
            Issue.record("Expected .image content block, got \(contentBlock)")
        }
    }

    @Test("image block with unsupported model throws unsupportedModel")
    func imageBlockWithUnsupportedModelThrows() throws {
        let source = AnthropicImageSource(type: "base64", mediaType: "image/png", data: "abc=")
        let block = AnthropicContentBlock(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            source: source
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        #expect(throws: ImageTranslationError.self) {
            try translator.translate(request: request, resolvedModelID: "us.amazon.nova-micro-v1:0", modelMapper: mapper)
        }
    }

    @Test("image block with unsupported mediaType throws unsupportedFormat")
    func imageBlockWithUnsupportedMediaTypeThrows() throws {
        let source = AnthropicImageSource(type: "base64", mediaType: "image/bmp", data: "Qk0=")
        let block = AnthropicContentBlock(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            source: source
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let modelID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        #expect(throws: ImageTranslationError.self) {
            try translator.translate(request: request, resolvedModelID: modelID, modelMapper: mapper)
        }
    }

    @Test("image block exceeding size limit throws imageTooLarge")
    func imageBlockExceedingSizeLimitThrows() throws {
        let largeBase64 = String(repeating: "A", count: 5_300_000)
        let source = AnthropicImageSource(type: "base64", mediaType: "image/jpeg", data: largeBase64)
        let block = AnthropicContentBlock(
            type: "image",
            text: nil,
            id: nil,
            name: nil,
            input: nil,
            toolUseId: nil,
            content: nil,
            source: source
        )
        let request = makeRequest(
            messages: [AnthropicMessage(role: "user", content: .blocks([block]))]
        )
        let modelID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        #expect(throws: ImageTranslationError.self) {
            try translator.translate(request: request, resolvedModelID: modelID, modelMapper: mapper)
        }
    }
}
