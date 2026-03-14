import Testing
import Foundation
import SotoCore
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

    @Test("intermediate chunk omits finish_reason entirely (not null)")
    func intermediateChunkFinishReasonIsAbsent() throws {
        let chunk = translator.streamChunk(text: "Hi", model: "m", completionID: "id")
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        let choices = json["choices"]
        guard case .array(let arr) = choices,
              case .object(let choice) = arr.first else {
            Issue.record("choices array missing or malformed")
            return
        }
        // finish_reason must be absent for intermediate chunks — never null
        #expect(choice["finish_reason"] == nil)
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

    // MARK: - Tool Calling

    @Test("toolUse stop reason maps to 'tool_calls'")
    func stopReasonToolUseMapsToToolCalls() {
        let chunk = translator.stopChunk(model: "m", completionID: "id", stopReason: .toolUse)
        #expect(chunk.choices[0].finishReason == "tool_calls")
    }

    @Test("toolCallStartChunk carries id, type, name and empty arguments")
    func toolCallStartChunkStructure() throws {
        let chunk = translator.toolCallStartChunk(
            index: 0, id: "call-123", name: "get_weather",
            model: "m", completionID: "id"
        )
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard case .array(let choices) = json["choices"],
              case .object(let choice) = choices.first,
              case .object(let delta) = choice["delta"],
              case .array(let toolCalls) = delta["tool_calls"],
              case .object(let tc) = toolCalls.first else {
            Issue.record("structure missing or malformed")
            return
        }
        #expect(tc["id"] == .string("call-123"))
        #expect(tc["type"] == .string("function"))
        #expect(choice["finish_reason"] == nil)
        // content must be null when tool_calls is present
        #expect(delta["content"] == .null)
        guard case .object(let fn) = tc["function"] else {
            Issue.record("function missing"); return
        }
        #expect(fn["name"] == .string("get_weather"))
        #expect(fn["arguments"] == .string(""))
    }

    @Test("toolCallDeltaChunk has nil id and nil type with argument delta")
    func toolCallDeltaChunkStructure() throws {
        let chunk = translator.toolCallDeltaChunk(
            index: 0, argumentsDelta: "{\"loc",
            model: "m", completionID: "id"
        )
        let data = try JSONEncoder().encode(chunk)
        let json = try JSONDecoder().decode([String: JSONValue].self, from: data)
        guard case .array(let choices) = json["choices"],
              case .object(let choice) = choices.first,
              case .object(let delta) = choice["delta"],
              case .array(let toolCalls) = delta["tool_calls"],
              case .object(let tc) = toolCalls.first else {
            Issue.record("structure missing or malformed")
            return
        }
        // id and type must be absent or null for delta chunks
        #expect(tc["id"] == nil || tc["id"] == .null)
        #expect(tc["type"] == nil || tc["type"] == .null)
        guard case .object(let fn) = tc["function"] else {
            Issue.record("function missing"); return
        }
        #expect(fn["arguments"] == .string("{\"loc"))
    }

    @Test("non-streaming response with toolUse block produces tool_calls")
    func nonStreamingToolUseBlockProducesToolCalls() {
        let toolInput: AWSDocument = .map(["location": .string("Boston")])
        let response = BedrockRuntime.ConverseResponse(
            metrics: BedrockRuntime.ConverseMetrics(latencyMs: 0),
            output: BedrockRuntime.ConverseOutput(
                message: BedrockRuntime.Message(
                    content: [.toolUse(BedrockRuntime.ToolUseBlock(
                        input: toolInput,
                        name: "get_weather",
                        toolUseId: "call-abc"
                    ))],
                    role: .assistant
                )
            ),
            stopReason: .toolUse,
            usage: BedrockRuntime.TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
        )
        let result = translator.translate(response: response, model: "m", completionID: "id")
        #expect(result.choices[0].finishReason == "tool_calls")
        let toolCalls = result.choices[0].message.toolCalls
        #expect(toolCalls != nil)
        #expect(toolCalls?.count == 1)
        #expect(toolCalls?.first?.function.name == "get_weather")
        #expect(toolCalls?.first?.id == "call-abc")
    }
}
