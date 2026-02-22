import Foundation
import SotoBedrockRuntime

struct AnthropicResponseTranslator: Sendable {

    // MARK: - Non-streaming

    func translate(
        response: BedrockRuntime.ConverseResponse,
        model: String,
        messageID: String
    ) -> AnthropicResponse {
        let content = translateOutputContent(response.output)
        return AnthropicResponse(
            id: messageID,
            type: "message",
            role: "assistant",
            content: content,
            model: model,
            stopReason: translateStopReason(response.stopReason),
            usage: AnthropicUsage(
                inputTokens: response.usage.inputTokens,
                outputTokens: response.usage.outputTokens
            )
        )
    }

    // MARK: - Streaming helpers

    /// Initial `message_start` SSE event. Usage is filled with zeros;
    /// real counts arrive in the final `message_delta` event.
    func messageStartSSE(messageID: String, model: String) -> String {
        sseEvent("message_start", data: """
        {"type":"message_start","message":{"id":"\(messageID)","type":"message","role":"assistant",\
        "content":[],"model":"\(jsonEscape(model))","stop_reason":null,\
        "usage":{"input_tokens":0,"output_tokens":0}}}
        """)
    }

    func pingSSE() -> String {
        sseEvent("ping", data: "{\"type\":\"ping\"}")
    }

    /// Translate one Bedrock stream event into zero or more Anthropic SSE strings.
    func translateStreamEvent(_ event: BedrockRuntime.ConverseStreamOutput) -> [String] {
        switch event {
        case .contentBlockStart(let e):  return [contentBlockStartSSE(e)]
        case .contentBlockDelta(let e):  return [contentBlockDeltaSSE(e)]
        case .contentBlockStop(let e):   return [contentBlockStopSSE(e)]
        default:                         return []
        }
    }

    /// Final `message_delta` + `message_stop` pair emitted after the stream ends.
    func finalSSE(stopReason: String, outputTokens: Int) -> String {
        let delta = sseEvent("message_delta", data: """
        {"type":"message_delta","delta":{"stop_reason":"\(stopReason)","stop_sequence":null},\
        "usage":{"output_tokens":\(outputTokens)}}
        """)
        let stop = sseEvent("message_stop", data: "{\"type\":\"message_stop\"}")
        return delta + stop
    }

    // MARK: - Stop reason

    func translateStopReason(_ reason: BedrockRuntime.StopReason?) -> String {
        guard let reason else { return "end_turn" }
        switch reason {
        case .endTurn:   return "end_turn"
        case .maxTokens: return "max_tokens"
        case .toolUse:   return "tool_use"
        default:         return "end_turn"
        }
    }

    // MARK: - Private

    private func translateOutputContent(_ output: BedrockRuntime.ConverseOutput?) -> [AnthropicContentBlock] {
        guard let message = output?.message else { return [] }
        return message.content.compactMap { block -> AnthropicContentBlock? in
            switch block {
            case .text(let t):
                return .text(t)
            case .toolUse(let tu):
                return .toolUse(
                    id: tu.toolUseId,
                    name: tu.name,
                    input: JSONValue.from(document: tu.input)
                )
            default:
                return nil
            }
        }
    }

    private func contentBlockStartSSE(_ e: BedrockRuntime.ContentBlockStartEvent) -> String {
        let blockJSON: String
        switch e.start {
        case .toolUse(let tu):
            blockJSON = """
            {"type":"tool_use","id":"\(jsonEscape(tu.toolUseId))","name":"\(jsonEscape(tu.name))","input":{}}
            """
        default:
            blockJSON = "{\"type\":\"text\",\"text\":\"\"}"
        }
        return sseEvent("content_block_start", data: """
        {"type":"content_block_start","index":\(e.contentBlockIndex),"content_block":\(blockJSON)}
        """)
    }

    private func contentBlockDeltaSSE(_ e: BedrockRuntime.ContentBlockDeltaEvent) -> String {
        let deltaJSON: String
        switch e.delta {
        case .text(let text):
            deltaJSON = "{\"type\":\"text_delta\",\"text\":\"\(jsonEscape(text))\"}"
        case .toolUse(let tu):
            deltaJSON = "{\"type\":\"input_json_delta\",\"partial_json\":\"\(jsonEscape(tu.input))\"}"
        default:
            return ""
        }
        return sseEvent("content_block_delta", data: """
        {"type":"content_block_delta","index":\(e.contentBlockIndex),"delta":\(deltaJSON)}
        """)
    }

    private func contentBlockStopSSE(_ e: BedrockRuntime.ContentBlockStopEvent) -> String {
        sseEvent("content_block_stop", data: """
        {"type":"content_block_stop","index":\(e.contentBlockIndex)}
        """)
    }

    private func sseEvent(_ event: String, data: String) -> String {
        "event: \(event)\ndata: \(data)\n\n"
    }

    private func jsonEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
         .replacingOccurrences(of: "\"", with: "\\\"")
         .replacingOccurrences(of: "\n", with: "\\n")
         .replacingOccurrences(of: "\r", with: "\\r")
         .replacingOccurrences(of: "\t", with: "\\t")
    }
}
