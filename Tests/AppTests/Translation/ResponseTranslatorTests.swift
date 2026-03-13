import Testing
import Foundation
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
        // content is nil in the model; it encodes as JSON null (not omitted)
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

    // MARK: - OpenAI streaming format conformance

    @Test("stop chunk delta encodes content as null (not an empty object)")
    func stopChunkDeltaHasExplicitContentNull() throws {
        let chunk = translator.stopChunk(model: "m", completionID: "id", stopReason: nil)
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard case .array(let arr) = json["choices"],
              case .object(let choice) = arr.first,
              case .object(let delta) = choice["delta"] else {
            Issue.record("choices/delta missing or malformed")
            return
        }
        // delta must NOT be an empty object — content key must be present (as null)
        #expect(delta["content"] != nil, "content key must always be present in delta")
        #expect(delta["content"] == .null)
    }

    @Test("intermediate chunk encodes finish_reason as null (not omitted)")
    func intermediateChunkFinishReasonIsExplicitNull() throws {
        let chunk = translator.streamChunk(text: "Hi", model: "m", completionID: "id")
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let choices = json["choices"]
        guard case .array(let arr) = choices,
              case .object(let choice) = arr.first else {
            Issue.record("choices array missing or malformed")
            return
        }
        // finish_reason key must be present and its value must be null
        #expect(choice["finish_reason"] != nil, "finish_reason key must always be present")
        #expect(choice["finish_reason"] == .null)
    }

    @Test("stop chunk encodes finish_reason as 'stop' (not null)")
    func stopChunkFinishReasonIsPresent() throws {
        let chunk = translator.stopChunk(model: "m", completionID: "id", stopReason: .endTurn)
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let choices = json["choices"]
        guard case .array(let arr) = choices,
              case .object(let choice) = arr.first else {
            Issue.record("choices array missing or malformed")
            return
        }
        #expect(choice["finish_reason"] == .string("stop"))
    }

    @Test("stop chunk for maxTokens encodes finish_reason as 'length'")
    func stopChunkMaxTokensFinishReasonIsLength() throws {
        let chunk = translator.stopChunk(model: "m", completionID: "id", stopReason: .maxTokens)
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let choices = json["choices"]
        guard case .array(let arr) = choices,
              case .object(let choice) = arr.first else {
            Issue.record("choices array missing or malformed")
            return
        }
        #expect(choice["finish_reason"] == .string("length"))
    }
}
