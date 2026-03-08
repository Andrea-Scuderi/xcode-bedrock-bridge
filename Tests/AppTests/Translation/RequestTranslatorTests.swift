import Testing
import Foundation
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
        let (system, messages, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
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
        let (_, messages, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
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
        let (_, _, inferenceConfig) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
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
        let (_, _, inferenceConfig) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
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
        let (_, _, inferenceConfig) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
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
        let (_, messages, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
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
        let (_, messages, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        #expect(messages.count == 3)
    }

    @Test("unknown role messages are dropped")
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
        let (_, messages, _) = try translator.translate(request: request, modelID: "model-id", modelMapper: mapper)
        // "function" role is unknown → dropped; leaves two separate user messages
        #expect(messages.count == 2)
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
        let (_, messages, _) = try translator.translate(request: request, modelID: modelID, modelMapper: mapper)
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
        let (_, messages, _) = try translator.translate(
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
