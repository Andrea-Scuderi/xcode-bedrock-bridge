import Testing
import SotoBedrockRuntime
@testable import App

@Suite("ResponseTranslator")
struct ResponseTranslatorTests {

    let translator = ResponseTranslator()

    @Test("stream chunk has correct format")
    func streamChunkFormat() {
        let chunk = translator.streamChunk(
            text: "Hello",
            model: "claude-3-5-sonnet",
            completionID: "chatcmpl-test"
        )
        #expect(chunk.object == "chat.completion.chunk")
        #expect(chunk.choices.count == 1)
        #expect(chunk.choices[0].delta.content == "Hello")
        #expect(chunk.choices[0].finishReason == nil)
    }

    @Test("stop chunk has finish reason 'stop' for nil stopReason")
    func stopChunkHasFinishReason() {
        let chunk = translator.stopChunk(
            model: "claude-3-5-sonnet",
            completionID: "chatcmpl-test",
            stopReason: nil
        )
        #expect(chunk.choices[0].finishReason == "stop")
        #expect(chunk.choices[0].delta.content == nil)
    }

    @Test("stream chunk with explicit finish reason propagates it")
    func streamChunkWithExplicitFinishReason() {
        let chunk = translator.streamChunk(
            text: "Last",
            model: "claude-3-5-sonnet",
            completionID: "chatcmpl-test",
            finishReason: "length"
        )
        #expect(chunk.choices[0].finishReason == "length")
    }

    @Test("maxTokens stop reason maps to 'length'")
    func stopChunkForMaxTokensReason() {
        let chunk = translator.stopChunk(
            model: "claude-3-5-sonnet",
            completionID: "chatcmpl-test",
            stopReason: .maxTokens
        )
        #expect(chunk.choices[0].finishReason == "length")
    }

    @Test("stop chunk model field matches input")
    func stopChunkModelPropagated() {
        let chunk = translator.stopChunk(
            model: "my-model",
            completionID: "chatcmpl-test",
            stopReason: nil
        )
        #expect(chunk.model == "my-model")
    }

    @Test("stream chunk object is 'chat.completion.chunk'")
    func streamChunkObjectIsChunkType() {
        let chunk = translator.streamChunk(
            text: "text",
            model: "claude",
            completionID: "id"
        )
        #expect(chunk.object == "chat.completion.chunk")
    }
}
