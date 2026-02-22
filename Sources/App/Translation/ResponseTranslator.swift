import Foundation
import SotoBedrockRuntime

struct ResponseTranslator: Sendable {

    /// Translate a Bedrock ConverseResponse into an OpenAI ChatCompletionResponse.
    func translate(
        response: BedrockRuntime.ConverseResponse,
        model: String,
        completionID: String
    ) -> ChatCompletionResponse {
        let content = extractContent(from: response.output)
        let finishReason = translateStopReason(response.stopReason)

        let choice = ChatChoice(
            index: 0,
            message: ChatMessage(role: "assistant", content: content),
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

    // MARK: - Private Helpers

    // ConverseOutput is a struct with an optional `message: Message?` field
    private func extractContent(from output: BedrockRuntime.ConverseOutput?) -> String {
        guard let message = output?.message else { return "" }
        return message.content.compactMap { block -> String? in
            switch block {
            case .text(let text): return text
            default: return nil
            }
        }.joined()
    }

    private func translateStopReason(_ reason: BedrockRuntime.StopReason?) -> String {
        guard let reason else { return "stop" }
        switch reason {
        case .endTurn:   return "stop"
        case .maxTokens: return "length"
        default:         return "stop"
        }
    }
}
