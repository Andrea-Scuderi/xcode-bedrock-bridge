import Testing
import VaporTesting
import SotoBedrockRuntime
import SotoCore
@testable import App

// MARK: - Mock

private struct MockBedrockConversable: BedrockConversable {
    enum Behavior { case success, failure(Error), toolUseResponse }
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
        case .toolUseResponse: return mockToolUseConverseResponse()
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
        onUsage: (@Sendable (_ inputTokens: Int, _ outputTokens: Int) -> Void)?,
        onStop: (@Sendable (_ stopReason: BedrockRuntime.StopReason?) -> Void)?
    ) async throws -> AsyncThrowingStream<String, Error> {
        switch behavior {
        case .success:
            return AsyncThrowingStream { c in c.yield("Hello"); c.finish() }
        case .failure(let e):
            return AsyncThrowingStream { c in c.finish(throwing: e) }
        case .toolUseResponse:
            return AsyncThrowingStream { c in c.yield(""); c.finish() }
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

private func mockToolUseConverseResponse() -> BedrockRuntime.ConverseResponse {
    let toolInput: AWSDocument = .map(["location": .string("Boston, MA")])
    return BedrockRuntime.ConverseResponse(
        metrics: BedrockRuntime.ConverseMetrics(latencyMs: 0),
        output: BedrockRuntime.ConverseOutput(
            message: BedrockRuntime.Message(
                content: [.toolUse(BedrockRuntime.ToolUseBlock(
                    input: toolInput,
                    name: "get_weather",
                    toolUseId: "tool-use-id-123"
                ))],
                role: .assistant
            )
        ),
        stopReason: .toolUse,
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

    // MARK: - Fix 4: unsupported parameter validation

    @Test("n greater than 1 returns 422")
    func nGreaterThan1Returns422() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"n":2}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .unprocessableEntity)
            }
        }
    }

    @Test("n equal to 1 is accepted")
    func nEqualTo1IsAccepted() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"n":1}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status != .unprocessableEntity)
            }
        }
    }

    @Test("response_format json_object returns 422")
    func responseFormatJsonObjectReturns422() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"response_format":{"type":"json_object"}}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .unprocessableEntity)
            }
        }
    }

    @Test("response_format text is accepted")
    func responseFormatTextIsAccepted() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"response_format":{"type":"text"}}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status != .unprocessableEntity)
            }
        }
    }

    @Test("non-empty tools returns 200 (tool calling supported)")
    func nonEmptyToolsReturns200() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"What is the weather in Boston?"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}},"required":["location"]}}}],"tool_choice":"auto"}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("tool_choice none with tools returns 200")
    func toolChoiceNoneReturns200() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"tools":[{"type":"function","function":{"name":"get_weather","parameters":{}}}],"tool_choice":"none"}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("response with tool_calls contains finish_reason tool_calls")
    func toolCallResponseHasCorrectFinishReason() async throws {
        try await withApp({ app in
            let mock = MockBedrockConversable(behavior: .toolUseResponse)
            let controller = ChatController(
                bedrockService: mock,
                modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
                requestTranslator: RequestTranslator(),
                responseTranslator: ResponseTranslator()
            )
            try app.register(collection: controller)
        }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"What is the weather?"}],"tools":[{"type":"function","function":{"name":"get_weather","description":"Get weather","parameters":{"type":"object","properties":{"location":{"type":"string"}}}}}]}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
                let json = try? JSONDecoder().decode([String: JSONValue].self, from: Data(res.body.readableBytesView))
                guard case .array(let choices) = json?["choices"],
                      case .object(let choice) = choices.first else {
                    Issue.record("choices missing or malformed")
                    return
                }
                #expect(choice["finish_reason"] == .string("tool_calls"))
                guard case .object(let message) = choice["message"],
                      case .array(let toolCalls) = message["tool_calls"],
                      case .object(let tc) = toolCalls.first,
                      case .string(let tcType) = tc["type"] else {
                    Issue.record("tool_calls missing or malformed")
                    return
                }
                #expect(tcType == "function")
            }
        }
    }

    @Test("ignored fields seed user frequency_penalty presence_penalty do not cause errors")
    func ignoredFieldsAreAccepted() async throws {
        try await withApp({ app in try configure(app: app) }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"seed":42,"user":"user-123","frequency_penalty":0.5,"presence_penalty":0.3,"logprobs":false}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("422 error body uses OpenAI error format")
    func unprocessableEntityReturnsOpenAIErrorFormat() async throws {
        try await withApp({ app in
            let mock = MockBedrockConversable(behavior: .success)
            let controller = ChatController(
                bedrockService: mock,
                modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
                requestTranslator: RequestTranslator(),
                responseTranslator: ResponseTranslator()
            )
            try app.grouped(OpenAIErrorMiddleware()).register(collection: controller)
        }) { app in
            let body = #"{"model":"claude-sonnet","messages":[{"role":"user","content":"hi"}],"n":2}"#
            var headers = HTTPHeaders()
            headers.contentType = .json
            try await app.test(.POST, "/v1/chat/completions", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .unprocessableEntity)
                let json = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: Data(res.body.readableBytesView))
                #expect(json != nil)
                #expect(json?.error.type == "invalid_request_error")
                #expect(json?.error.message.isEmpty == false)
            }
        }
    }
}
