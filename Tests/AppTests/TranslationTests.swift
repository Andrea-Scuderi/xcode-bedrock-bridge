import XCTest
@testable import App

final class TranslationTests: XCTestCase {

    // MARK: - ModelMapper

    func testModelMapperGPT4MapsToSonnet() {
        let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
        XCTAssertEqual(
            mapper.bedrockModelID(for: "gpt-4"),
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        )
    }

    func testModelMapperGPT35MapsToHaiku() {
        let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
        XCTAssertEqual(
            mapper.bedrockModelID(for: "gpt-3.5-turbo"),
            "us.anthropic.claude-haiku-4-5-20251001-v1:0"
        )
    }

    func testModelMapperPassthroughBedrockID() {
        let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
        let nativeID = "us.anthropic.claude-3-opus-20240229-v1:0"
        XCTAssertEqual(mapper.bedrockModelID(for: nativeID), nativeID)
    }

    func testModelMapperUnknownIDUsesDefault() {
        let defaultModel = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        let mapper = ModelMapper(defaultModel: defaultModel)
        XCTAssertEqual(mapper.bedrockModelID(for: "some-unknown-model"), defaultModel)
    }

    func testModelMapperClaudeSonnetAlias() {
        let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
        XCTAssertEqual(
            mapper.bedrockModelID(for: "claude-3-5-sonnet"),
            "us.anthropic.claude-3-5-sonnet-20241022-v2:0"
        )
    }

    // MARK: - RequestTranslator

    func testRequestTranslatorExtractsSystemMessages() {
        let translator = RequestTranslator()
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "system", content: "You are a helpful assistant."),
                ChatMessage(role: "user", content: "Hello"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )

        let (system, messages, _) = translator.translate(request: request, modelID: "model-id")

        XCTAssertEqual(system.count, 1)
        XCTAssertEqual(messages.count, 1)
    }

    func testRequestTranslatorConsolidatesConsecutiveUserMessages() {
        let translator = RequestTranslator()
        let request = ChatCompletionRequest(
            model: "gpt-4",
            messages: [
                ChatMessage(role: "user", content: "First message"),
                ChatMessage(role: "user", content: "Second message"),
            ],
            maxTokens: 100,
            temperature: nil,
            topP: nil,
            stream: nil,
            stop: nil
        )

        let (_, messages, _) = translator.translate(request: request, modelID: "model-id")

        // Two consecutive user messages should be merged into one
        XCTAssertEqual(messages.count, 1)
    }

    func testRequestTranslatorInferenceConfig() {
        let translator = RequestTranslator()
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

        XCTAssertEqual(inferenceConfig.maxTokens, 256)
        XCTAssertEqual(inferenceConfig.temperature ?? 0, Float(0.7), accuracy: Float(0.001))
        XCTAssertEqual(inferenceConfig.topP ?? 0, Float(0.9), accuracy: Float(0.001))
    }

    // MARK: - ResponseTranslator

    func testResponseTranslatorStreamChunkFormat() {
        let translator = ResponseTranslator()
        let chunk = translator.streamChunk(
            text: "Hello",
            model: "claude-3-5-sonnet",
            completionID: "chatcmpl-test"
        )

        XCTAssertEqual(chunk.object, "chat.completion.chunk")
        XCTAssertEqual(chunk.choices.count, 1)
        XCTAssertEqual(chunk.choices[0].delta.content, "Hello")
        XCTAssertNil(chunk.choices[0].finishReason)
    }

    func testResponseTranslatorStopChunkHasFinishReason() {
        let translator = ResponseTranslator()
        let chunk = translator.stopChunk(
            model: "claude-3-5-sonnet",
            completionID: "chatcmpl-test",
            stopReason: nil
        )

        XCTAssertEqual(chunk.choices[0].finishReason, "stop")
        XCTAssertNil(chunk.choices[0].delta.content)
    }
}
