import Testing
import Foundation
import Vapor
@testable import App

@Suite("RequestTranslator")
struct RequestTranslatorTests {

    let translator = RequestTranslator()
    let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")

    @Test("system messages extracted from conversation")
    func extractsSystemMessages() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "system", content: "You are helpful."),
                ChatMessage(role: "user", content: "Hello"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (system, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(system.count == 1)
        #expect(messages.count == 1)
    }

    @Test("consecutive user messages consolidated into one")
    func consolidatesConsecutiveUserMessages() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "First"),
                ChatMessage(role: "user", content: "Second"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(messages.count == 1)
    }

    @Test("inference config populated with all fields")
    func inferenceConfigPopulated() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Hi")],
            maxTokens: 256,
            temperature: 0.7,
            topP: 0.9,
            stream: nil,
            stop: nil
        )
        let (_, _, inferenceConfig, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(inferenceConfig.maxTokens == 256)
        #expect(abs((inferenceConfig.temperature ?? 0) - Float(0.7)) < Float(0.001))
        #expect(abs((inferenceConfig.topP ?? 0) - Float(0.9)) < Float(0.001))
    }

    @Test("nil maxTokens defaults to 4096")
    func defaultsMaxTokensTo4096WhenNil() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Hi")],
            maxTokens: nil,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, _, inferenceConfig, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(inferenceConfig.maxTokens == 4096)
    }

    @Test("nil temperature produces nil in inference config")
    func nilTemperatureProducesNilInConfig() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Hi")],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, _, inferenceConfig, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(inferenceConfig.temperature == nil)
    }

    @Test("consecutive assistant messages consolidated into one")
    func consolidatesConsecutiveAssistantMessages() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "assistant", content: "First"),
                ChatMessage(role: "assistant", content: "Second"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(messages.count == 1)
    }

    @Test("alternating user/assistant roles are not consolidated")
    func alternatingRolesNotConsolidated() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "A"),
                ChatMessage(role: "assistant", content: "B"),
                ChatMessage(role: "user", content: "C"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(messages.count == 3)
    }

    @Test("unknown role messages are dropped and adjacent same-role messages merge")
    func unknownRoleIsDropped() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "Hello"),
                ChatMessage(role: "function", content: "result"),
                ChatMessage(role: "user", content: "Continue"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        // "function" role is unknown → dropped; the two adjacent user messages are then merged into one
        #expect(messages.count == 1)
    }

    // MARK: - Tool Calling

    @Test("tool role message maps to Bedrock user toolResult block")
    func toolRoleMessageMapsToToolResult() throws {
        let toolCallMsg = ChatMessage(role: "tool", content: "It is sunny", toolCallId: "call-123")
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "What is the weather?"),
                ChatMessage(role: "assistant", content: "", toolCalls: [
                    ToolCall(id: "call-123", type: "function", index: nil,
                             function: ToolCallFunction(name: "get_weather", arguments: "{\"location\":\"Boston\"}"))
                ]),
                toolCallMsg,
            ],
            maxTokens: 100
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        // user, assistant, user(toolResult) — last two user blocks may merge
        #expect(messages.count == 3 || messages.count == 2)
        // Last message must be a user message containing a toolResult block
        let lastMsg = messages.last!
        #expect(lastMsg.role == .user)
        let hasToolResult = lastMsg.content.contains { block in
            if case .toolResult = block { return true }
            return false
        }
        #expect(hasToolResult)
    }

    @Test("assistant message with toolCalls produces toolUse content blocks")
    func assistantWithToolCallsProducesToolUseBlocks() throws {
        let toolCall = ToolCall(
            id: "call-abc",
            type: "function",
            index: nil,
            function: ToolCallFunction(name: "get_weather", arguments: "{\"location\":\"Boston\"}")
        )
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "What is the weather?"),
                ChatMessage(role: "assistant", content: "", toolCalls: [toolCall]),
            ],
            maxTokens: 100
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(messages.count == 2)
        let assistantMsg = messages[1]
        #expect(assistantMsg.role == .assistant)
        let hasToolUse = assistantMsg.content.contains { block in
            if case .toolUse = block { return true }
            return false
        }
        #expect(hasToolUse)
    }

    @Test("tools translated to Bedrock ToolConfiguration")
    func toolsTranslatedToToolConfig() throws {
        let toolsJSON: JSONValue = .array([
            .object([
                "type": .string("function"),
                "function": .object([
                    "name": .string("get_weather"),
                    "description": .string("Get current weather"),
                    "parameters": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "location": .object(["type": .string("string")])
                        ])
                    ])
                ])
            ])
        ])
        guard case .array(let tools) = toolsJSON else {
            Issue.record("Expected array"); return
        }
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Weather?")],
            maxTokens: 100,
            tools: tools,
            toolChoice: .string("auto")
        )
        let (_, _, _, toolConfig) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(toolConfig != nil)
        #expect(toolConfig?.tools.count == 1)
    }

    @Test("tool_choice none produces nil toolConfig")
    func toolChoiceNoneProducesNilConfig() throws {
        let tools: [JSONValue] = [
            .object([
                "type": .string("function"),
                "function": .object(["name": .string("get_weather"), "parameters": .object([:])])
            ])
        ]
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "hi")],
            maxTokens: 100,
            tools: tools,
            toolChoice: .string("none")
        )
        let (_, _, _, toolConfig) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(toolConfig == nil)
    }

    @Test("consecutive tool messages merge into single Bedrock user message")
    func consecutiveToolMessagesMerge() throws {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "Run tools"),
                ChatMessage(role: "assistant", content: "", toolCalls: [
                    ToolCall(id: "call-1", type: "function", index: nil,
                             function: ToolCallFunction(name: "tool_a", arguments: "{}")),
                    ToolCall(id: "call-2", type: "function", index: nil,
                             function: ToolCallFunction(name: "tool_b", arguments: "{}"))
                ]),
                ChatMessage(role: "tool", content: "Result A", toolCallId: "call-1"),
                ChatMessage(role: "tool", content: "Result B", toolCallId: "call-2"),
            ],
            maxTokens: 100
        )
        let (_, messages, _, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        // user, assistant, user(2 toolResults merged)
        #expect(messages.count == 3)
        let lastMsg = messages[2]
        #expect(lastMsg.role == .user)
        #expect(lastMsg.content.count == 2)
    }

    // MARK: - Image Support

    @Test("image part for vision-capable model produces .image content block")
    func imagePartForCapableModelProducesImageBlock() throws {
        // Construct a message with an image_url content part via JSON decoding.
        let dataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let json = """
        {"role":"user","content":[{"type":"text","text":"What is in this image?"},{"type":"image_url","image_url":{"url":"\(dataURL)"}}]}
        """
        let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [msg],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let modelID = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        let (_, messages, _, _) = try translator.translate(request: request, modelID: modelID, modelMapper: mapper)
        #expect(messages.count == 1)
        let content = messages[0].content
        // Should have a text block and an image block
        #expect(content.count == 2)
        let hasImageBlock = content.contains { block in
            if case .image = block { return true }
            return false
        }
        #expect(hasImageBlock)
    }

    @Test("image part for text-only model throws unsupportedModel")
    func imagePartForTextOnlyModelThrows() throws {
        let dataURL = "data:image/png;base64,abc="
        let json = """
        {"role":"user","content":[{"type":"image_url","image_url":{"url":"\(dataURL)"}}]}
        """
        let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        let request = ChatCompletionRequest(
            model: "nova-micro",
            messages: [msg],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        #expect(throws: ImageTranslationError.self) {
            try translator.translate(request: request, modelID: "us.amazon.nova-micro-v1:0", modelMapper: mapper)
        }
    }

    @Test("image with unsupported format throws unsupportedFormat")
    func imageWithUnsupportedFormatThrows() throws {
        // BMP is not supported
        let dataURL = "data:image/bmp;base64,Qk0="
        let json = """
        {"role":"user","content":[{"type":"image_url","image_url":{"url":"\(dataURL)"}}]}
        """
        let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [msg],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        #expect(throws: ImageTranslationError.self) {
            try translator.translate(request: request, modelID: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", modelMapper: mapper)
        }
    }

    @Test("oversized image throws imageTooLarge")
    func oversizedImageThrows() throws {
        // Generate a base64 string large enough to exceed 3.75 MB decoded.
        // 3_932_160 decoded bytes → ~5_242_880 base64 chars; use slightly more.
        let largeBase64 = String(repeating: "A", count: 5_300_000)
        let dataURL = "data:image/jpeg;base64,\(largeBase64)"
        let json = """
        {"role":"user","content":[{"type":"image_url","image_url":{"url":"\(dataURL)"}}]}
        """
        let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [msg],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        #expect(throws: ImageTranslationError.self) {
            try translator.translate(request: request, modelID: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", modelMapper: mapper)
        }
    }

    @Test("text-image-text in same message produces correct block ordering")
    func textImageTextProducesCorrectBlocks() throws {
        let dataURL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
        let json = """
        {"role":"user","content":[{"type":"text","text":"Before"},{"type":"image_url","image_url":{"url":"\(dataURL)"}},{"type":"text","text":"After"}]}
        """
        let msg = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
        let request = ChatCompletionRequest(
            model: "claude-sonnet-4-5",
            messages: [msg],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, messages, _, _) = try translator.translate(
            request: request,
            modelID: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            modelMapper: mapper
        )
        #expect(messages.count == 1)
        let content = messages[0].content
        // text("Before"), image(...), text("After")
        #expect(content.count == 3)
        if case .text(let t) = content[0] { #expect(t == "Before") } else { Issue.record("Expected text block at index 0") }
        if case .image = content[1] { } else { Issue.record("Expected image block at index 1") }
        if case .text(let t) = content[2] { #expect(t == "After") } else { Issue.record("Expected text block at index 2") }
    }
}
