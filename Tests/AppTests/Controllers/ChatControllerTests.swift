import Testing
import VaporTesting
import SotoBedrockRuntime
@testable import App

// MARK: - Mock

private struct MockBedrockConversable: BedrockConversable {
    enum Behavior { case success, failure(Error) }
    let behavior: Behavior

    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> BedrockRuntime.ConverseResponse {
        switch behavior {
        case .success: return mockConverseResponse()
        case .failure(let e): throw e
        }
    }

    func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error> {
        throw MockError.notImplemented
    }

    func converseStream(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        onUsage: (@Sendable (_ inputTokens: Int, _ outputTokens: Int) -> Void)?
    ) async throws -> AsyncThrowingStream<String, Error> {
        switch behavior {
        case .success:
            return AsyncThrowingStream { c in c.yield("Hello"); c.finish() }
        case .failure(let e):
            return AsyncThrowingStream { c in c.finish(throwing: e) }
        }
    }
}

private enum MockError: Error {
    case notImplemented
}

private func mockConverseResponse() -> BedrockRuntime.ConverseResponse {
    BedrockRuntime.ConverseResponse(
        metrics: BedrockRuntime.ConverseMetrics(latencyMs: 0),
        output: BedrockRuntime.ConverseOutput(
            message: BedrockRuntime.Message(
                content: [.text("Hello from mock")],
                role: .assistant
            )
        ),
        stopReason: .endTurn,
        usage: BedrockRuntime.TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
    )
}

// MARK: - Suite

@Suite("ChatController input validation")
struct ChatControllerInputValidationTests {

    private func configure(app: Application, behavior: MockBedrockConversable.Behavior = .success) throws {
        let mock = MockBedrockConversable(behavior: behavior)
        let controller = ChatController(
            bedrockService: mock,
            modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
            requestTranslator: RequestTranslator(),
            responseTranslator: ResponseTranslator()
        )
        try app.register(collection: controller)
    }

    @Test("model name at limit is accepted")
    func modelNameAtLimitIsAccepted() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let longModel = String(repeating: "a", count: 128)
            let body = """
            {"model":"\(longModel)","messages":[{"role":"user","content":"hi"}],"max_tokens":10}
            """
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                // Model name is valid (128 chars) — mock returns 200, not .badRequest.
                #expect(res.status != .badRequest)
            }
        }
    }

    @Test("model name exceeding 128 chars returns 400")
    func modelNameTooLongReturns400() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let longModel = String(repeating: "a", count: 129)
            let body = """
            {"model":"\(longModel)","messages":[{"role":"user","content":"hi"}],"max_tokens":10}
            """
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test("exactly 100 messages is accepted")
    func exactly100MessagesIsAccepted() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let msgs = (0..<100).map { _ in "{\"role\":\"user\",\"content\":\"hi\"}" }.joined(separator: ",")
            let body = "{\"model\":\"claude-sonnet\",\"messages\":[\(msgs)],\"max_tokens\":10}"
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                // Guard passes; mock handles the Bedrock call — no real AWS call made.
                #expect(res.status != .badRequest)
            }
        }
    }

    @Test("101 messages returns 400")
    func tooManyMessagesReturns400() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let msgs = (0..<101).map { _ in "{\"role\":\"user\",\"content\":\"hi\"}" }.joined(separator: ",")
            let body = "{\"model\":\"claude-sonnet\",\"messages\":[\(msgs)],\"max_tokens\":10}"
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }

    @Test("message content at 65536 chars is accepted")
    func messageContentAtLimitIsAccepted() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let longText = String(repeating: "x", count: 65_536)
            let body = "{\"model\":\"claude-sonnet\",\"messages\":[{\"role\":\"user\",\"content\":\"\(longText)\"}],\"max_tokens\":10}"
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status != .badRequest)
            }
        }
    }

    @Test("message content exceeding 65536 chars returns 400")
    func messageContentTooLongReturns400() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let longText = String(repeating: "x", count: 65_537)
            let body = "{\"model\":\"claude-sonnet\",\"messages\":[{\"role\":\"user\",\"content\":\"\(longText)\"}],\"max_tokens\":10}"
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .badRequest)
            }
        }
    }
}
