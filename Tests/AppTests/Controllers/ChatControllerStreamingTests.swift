import Testing
import VaporTesting
import SotoBedrockRuntime
@testable import App

// MARK: - Mock

private struct MockStreamingBedrock: BedrockConversable {
    enum Behavior { case failDuringStream }
    let behavior: Behavior

    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> BedrockRuntime.ConverseResponse {
        throw MockStreamingError.notImplemented
    }

    func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error> {
        throw MockStreamingError.notImplemented
    }

    func converseStream(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        onUsage: (@Sendable (_ inputTokens: Int, _ outputTokens: Int) -> Void)?,
        onStop: (@Sendable (_ stopReason: BedrockRuntime.StopReason?) -> Void)?
    ) async throws -> AsyncThrowingStream<String, Error> {
        // Returns a stream that immediately throws to simulate a mid-stream Bedrock error
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: MockStreamingError.bedrockFailure)
        }
    }
}

private enum MockStreamingError: Error {
    case notImplemented
    case bedrockFailure
}

private func configure(app: Application) throws {
    let mock = MockStreamingBedrock(behavior: .failDuringStream)
    let controller = ChatController(
        bedrockService: mock,
        modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
        requestTranslator: RequestTranslator(),
        responseTranslator: ResponseTranslator()
    )
    try app.register(collection: controller)
}

// MARK: - Suite

@Suite("ChatController streaming")
struct ChatControllerStreamingTests {

    @Test("streaming Bedrock error closes connection without non-standard error SSE event")
    func streamingErrorClosesCleanly() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"stream":true}"#
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                // Response starts as 200 SSE (stream was opened successfully)
                #expect(res.status == .ok)
                #expect(res.headers.contentType?.description.contains("text/event-stream") == true)
                // Body must NOT contain the old non-standard "event: error" SSE format
                let bodyString = res.body.string
                #expect(!bodyString.contains("event: error"))
            }
        }
    }

    @Test("streaming Bedrock error does not emit data after stream failure")
    func streamingErrorEmitsNoDanglingData() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"stream":true}"#
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                let bodyString = res.body.string
                // No partial JSON error object should be in the stream body
                #expect(!bodyString.contains("\"error\":{"))
            }
        }
    }
}
