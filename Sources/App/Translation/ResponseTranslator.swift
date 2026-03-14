import Foundation
import SotoCore
import SotoBedrockRuntime

struct ResponseTranslator: Sendable {

    /// Translate a Bedrock ConverseResponse into an OpenAI ChatCompletionResponse.
    func translate(
        response: BedrockRuntime.ConverseResponse,
        model: String,
        completionID: String
    ) -> ChatCompletionResponse {
        let (text, toolCalls) = extractOutputBlocks(from: response.output)
        let finishReason = translateStopReason(response.stopReason)

        let message = ChatMessage(
            role: "assistant",
            content: text ?? "",
            toolCalls: toolCalls
        )
        let choice = ChatChoice(
            index: 0,
            message: message,
            finishReason: finishReason
        )

        // TokenUsage and its fields (inputTokens, outputTokens) are non-optional
        let usage = UsageInfo(
            promptTokens: response.usage.inputTokens,
            completionTokens: response.usage.outputTokens,
            totalTokens: response.usage.totalTokens
        )

        return ChatCompletionResponse(
            id: completionID,
            object: "chat.completion",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [choice],
            usage: usage
        )
    }

    /// Build a streaming SSE chunk for a text delta.
    func streamChunk(
        text: String,
        model: String,
        completionID: String,
        finishReason: String? = nil
    ) -> ChatCompletionChunk {
        let delta = ChunkDelta(role: nil, content: text)
        let choice = ChunkChoice(index: 0, delta: delta, finishReason: finishReason)
        return ChatCompletionChunk(
            id: completionID,
            object: "chat.completion.chunk",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [choice]
        )
    }

    /// Build the final stop chunk.
    func stopChunk(
        model: String,
        completionID: String,
        stopReason: BedrockRuntime.StopReason?
    ) -> ChatCompletionChunk {
        let finishReason = stopReason.map { translateStopReason($0) } ?? "stop"
        let delta = ChunkDelta(role: nil, content: nil)
        let choice = ChunkChoice(index: 0, delta: delta, finishReason: finishReason)
        return ChatCompletionChunk(
            id: completionID,
            object: "chat.completion.chunk",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [choice]
        )
    }

    /// Build the first tool_call delta chunk (carries id, type, name, empty arguments).
    func toolCallStartChunk(
        index: Int,
        id: String,
        name: String,
        model: String,
        completionID: String
    ) -> ChatCompletionChunk {
        let toolCall = ToolCall(
            id: id,
            type: "function",
            index: index,
            function: ToolCallFunction(name: name, arguments: "")
        )
        let delta = ChunkDelta(role: nil, content: nil, toolCalls: [toolCall])
        let choice = ChunkChoice(index: 0, delta: delta, finishReason: nil)
        return ChatCompletionChunk(
            id: completionID,
            object: "chat.completion.chunk",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [choice]
        )
    }

    /// Build a streaming argument-delta chunk for a tool call.
    func toolCallDeltaChunk(
        index: Int,
        argumentsDelta: String,
        model: String,
        completionID: String
    ) -> ChatCompletionChunk {
        let toolCall = ToolCall(
            id: nil,
            type: nil,
            index: index,
            function: ToolCallFunction(name: nil, arguments: argumentsDelta)
        )
        let delta = ChunkDelta(role: nil, content: nil, toolCalls: [toolCall])
        let choice = ChunkChoice(index: 0, delta: delta, finishReason: nil)
        return ChatCompletionChunk(
            id: completionID,
            object: "chat.completion.chunk",
            created: Int(Date().timeIntervalSince1970),
            model: model,
            choices: [choice]
        )
    }

    // MARK: - Private Helpers

    /// Extract text and tool_calls from a Bedrock ConverseOutput.
    private func extractOutputBlocks(
        from output: BedrockRuntime.ConverseOutput?
    ) -> (text: String?, toolCalls: [ToolCall]?) {
        guard let message = output?.message else { return (nil, nil) }
        var textParts: [String] = []
        var toolCalls: [ToolCall] = []

        for block in message.content {
            switch block {
            case .text(let t):
                textParts.append(t)
            case .toolUse(let tu):
                let arguments = encodeToolInput(tu.input)
                toolCalls.append(ToolCall(
                    id: tu.toolUseId,
                    type: "function",
                    index: nil,
                    function: ToolCallFunction(name: tu.name, arguments: arguments)
                ))
            default:
                break
            }
        }

        let text: String? = textParts.isEmpty ? nil : textParts.joined()
        return (text, toolCalls.isEmpty ? nil : toolCalls)
    }

    /// Encode a Bedrock AWSDocument tool input to a JSON object string.
    /// Returns `nil` for empty or non-object inputs (encodes as `null` in JSON)
    /// rather than the ambiguous `"{}"` empty-object string.
    private func encodeToolInput(_ doc: AWSDocument) -> String? {
        let jsonValue = JSONValue.from(document: doc)
        guard case .object(let map) = jsonValue, !map.isEmpty else { return nil }
        guard let data = try? JSONEncoder().encode(jsonValue),
              let str = String(data: data, encoding: .utf8),
              !str.isEmpty else {
            return nil
        }
        return str
    }

    func translateStopReason(_ reason: BedrockRuntime.StopReason?) -> String {
        guard let reason else { return "stop" }
        switch reason {
        case .endTurn:   return "stop"
        case .maxTokens: return "length"
        case .toolUse:   return "tool_calls"
        default:         return "stop"
        }
    }
}
