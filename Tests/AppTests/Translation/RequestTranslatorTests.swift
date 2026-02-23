import Testing
@testable import App

@Suite("RequestTranslator")
struct RequestTranslatorTests {

    let translator = RequestTranslator()

    @Test("system messages extracted from conversation")
    func extractsSystemMessages() {
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
        let (system, messages, _) = translator.translate(request: request, modelID: "model-id")
        #expect(system.count == 1)
        #expect(messages.count == 1)
    }

    @Test("consecutive user messages consolidated into one")
    func consolidatesConsecutiveUserMessages() {
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
        let (_, messages, _) = translator.translate(request: request, modelID: "model-id")
        #expect(messages.count == 1)
    }

    @Test("inference config populated with all fields")
    func inferenceConfigPopulated() {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Hi")],
            maxTokens: 256,
            temperature: 0.7,
            topP: 0.9,
            stream: nil,
            stop: nil
        )
        let (_, _, inferenceConfig) = translator.translate(request: request, modelID: "model-id")
        #expect(inferenceConfig.maxTokens == 256)
        #expect(abs((inferenceConfig.temperature ?? 0) - Float(0.7)) < Float(0.001))
        #expect(abs((inferenceConfig.topP ?? 0) - Float(0.9)) < Float(0.001))
    }

    @Test("nil maxTokens defaults to 4096")
    func defaultsMaxTokensTo4096WhenNil() {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Hi")],
            maxTokens: nil,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, _, inferenceConfig) = translator.translate(request: request, modelID: "model-id")
        #expect(inferenceConfig.maxTokens == 4096)
    }

    @Test("nil temperature produces nil in inference config")
    func nilTemperatureProducesNilInConfig() {
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [ChatMessage(role: "user", content: "Hi")],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )
        let (_, _, inferenceConfig) = translator.translate(request: request, modelID: "model-id")
        #expect(inferenceConfig.temperature == nil)
    }

    @Test("consecutive assistant messages consolidated into one")
    func consolidatesConsecutiveAssistantMessages() {
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
        let (_, messages, _) = translator.translate(request: request, modelID: "model-id")
        #expect(messages.count == 1)
    }

    @Test("alternating user/assistant roles are not consolidated")
    func alternatingRolesNotConsolidated() {
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
        let (_, messages, _) = translator.translate(request: request, modelID: "model-id")
        #expect(messages.count == 3)
    }

    @Test("unknown role messages are dropped")
    func unknownRoleIsDropped() {
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
        let (_, messages, _) = translator.translate(request: request, modelID: "model-id")
        // "function" role is unknown → dropped; leaves two separate user messages
        #expect(messages.count == 2)
    }
}
