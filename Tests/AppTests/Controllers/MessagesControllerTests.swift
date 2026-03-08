import Testing
import VaporTesting
import SotoBedrockRuntime
import SotoCore
@testable import App

// MARK: - Mock

private struct MockBedrockConversable: BedrockConversable {
    enum Behavior {
        case success(BedrockRuntime.ConverseResponse)
        case streamSuccess([BedrockRuntime.ConverseStreamOutput])
        case failure(Error)
    }

    let behavior: Behavior

    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> BedrockRuntime.ConverseResponse {
        switch behavior {
        case .success(let response): return response
        case .streamSuccess:         throw MockBedrockError.wrongMethodCalled
        case .failure(let error):    throw error
        }
    }

    func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error> {
        switch behavior {
        case .streamSuccess(let events):
            return AsyncThrowingStream { continuation in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        case .success:            throw MockBedrockError.wrongMethodCalled
        case .failure(let error): throw error
        }
    }

    func converseStream(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        onUsage: (@Sendable (_ inputTokens: Int, _ outputTokens: Int) -> Void)?
    ) async throws -> AsyncThrowingStream<String, Error> {
        throw MockBedrockError.wrongMethodCalled
    }
}

private enum MockBedrockError: Error {
    case wrongMethodCalled
}

private let mockThrottlingError: Error = AWSResponseError(errorCode: "ThrottlingException")

// MARK: - Helpers

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

private func minimalStreamEvents() -> [BedrockRuntime.ConverseStreamOutput] {
    [
        .contentBlockDelta(BedrockRuntime.ContentBlockDeltaEvent(
            contentBlockIndex: 0,
            delta: .text("Hello")
        )),
        .contentBlockStop(BedrockRuntime.ContentBlockStopEvent(
            contentBlockIndex: 0
        )),
        .messageStop(BedrockRuntime.MessageStopEvent(
            stopReason: .endTurn
        )),
        .metadata(BedrockRuntime.ConverseStreamMetadataEvent(
            metrics: BedrockRuntime.ConverseStreamMetrics(latencyMs: 0),
            usage: BedrockRuntime.TokenUsage(inputTokens: 10, outputTokens: 5, totalTokens: 15)
        )),
    ]
}

private func toolUseConverseResponse() -> BedrockRuntime.ConverseResponse {
    BedrockRuntime.ConverseResponse(
        metrics: BedrockRuntime.ConverseMetrics(latencyMs: 0),
        output: BedrockRuntime.ConverseOutput(
            message: BedrockRuntime.Message(
                content: [
                    .text("I'll read that file."),
                    .toolUse(BedrockRuntime.ToolUseBlock(
                        input: .map(["filePath": .string("src/main.swift")]),
                        name: "XcodeRead",
                        toolUseId: "tooluse_abc123",
                        type: .toolUse
                    ))
                ],
                role: .assistant
            )
        ),
        stopReason: .toolUse,
        usage: BedrockRuntime.TokenUsage(inputTokens: 100, outputTokens: 50, totalTokens: 150)
    )
}

private func toolUseStreamEvents() -> [BedrockRuntime.ConverseStreamOutput] {
    [
        .contentBlockStart(BedrockRuntime.ContentBlockStartEvent(
            contentBlockIndex: 0,
            start: .toolUse(BedrockRuntime.ToolUseBlockStart(
                name: "XcodeRead",
                toolUseId: "tooluse_abc123",
                type: .toolUse
            ))
        )),
        .contentBlockDelta(BedrockRuntime.ContentBlockDeltaEvent(
            contentBlockIndex: 0,
            delta: .toolUse(BedrockRuntime.ToolUseBlockDelta(input: "{\"filePath\":\"src/main.swift\"}"))
        )),
        .contentBlockStop(BedrockRuntime.ContentBlockStopEvent(
            contentBlockIndex: 0
        )),
        .messageStop(BedrockRuntime.MessageStopEvent(
            stopReason: .toolUse
        )),
        .metadata(BedrockRuntime.ConverseStreamMetadataEvent(
            metrics: BedrockRuntime.ConverseStreamMetrics(latencyMs: 0),
            usage: BedrockRuntime.TokenUsage(inputTokens: 100, outputTokens: 50, totalTokens: 150)
        )),
    ]
}

private func configureMessagesApp(app: Application, behavior: MockBedrockConversable.Behavior) throws {
    let mock = MockBedrockConversable(behavior: behavior)
    let controller = MessagesController(
        bedrockService: mock,
        modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
        requestTranslator: AnthropicRequestTranslator(),
        responseTranslator: AnthropicResponseTranslator()
    )
    try app.register(collection: controller)
}

// MARK: - Token Counting Tests

@Suite("MessagesController Token Counting")
struct MessagesControllerTests {

    @Test("single 12-char message estimates 3 tokens")
    func countTokensSingleMessageEstimatesCorrectly() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            // "Hello, world" = 12 chars → 12 / 4 = 3 tokens
            let body = """
            {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello, world"}],"max_tokens":100}
            """
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                    #expect(resp.inputTokens == 3)
                }
            }
        }
    }

    @Test("2-char message returns minimum of 1 token")
    func countTokensShortMessageReturnsMinimumOne() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            // "Hi" = 2 chars → 2 / 4 = 0 → max(1, 0) = 1 token
            let body = """
            {"model":"claude-sonnet","messages":[{"role":"user","content":"Hi"}],"max_tokens":100}
            """
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                    #expect(resp.inputTokens == 1)
                }
            }
        }
    }

    @Test("system prompt chars counted toward total")
    func countTokensSystemPromptCounts() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            // "Hello" (5) + "Hi" (2) = 7 chars → 7 / 4 = 1 token
            let body = """
            {"model":"claude-sonnet","messages":[{"role":"user","content":"Hi"}],"system":"Hello","max_tokens":100}
            """
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                    #expect(resp.inputTokens == 1)
                }
            }
        }
    }

    @Test("multiple messages chars aggregated")
    func countTokensMultipleMessagesAggregates() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            // "Hello!!!" (8) + "Worldxxx" (8) = 16 chars → 16 / 4 = 4 tokens
            let body = """
            {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello!!!"},{"role":"assistant","content":"Worldxxx"}],"max_tokens":100}
            """
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages/count_tokens", headers: headers, body: ByteBuffer(string: body)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicCountTokensResponse.self) {
                    #expect(resp.inputTokens == 4)
                }
            }
        }
    }
}

// MARK: - Non-Streaming Tests

@Suite("MessagesController non-streaming")
struct MessagesControllerNonStreamingTests {

    private let validBody = """
    {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello"}],"max_tokens":100}
    """

    @Test("returns OK for valid request")
    func returnsOKForValidRequest() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("response contains required fields")
    func responseContainsRequiredFields() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicResponse.self) {
                    #expect(resp.type == "message")
                    #expect(resp.role == "assistant")
                    #expect(!resp.id.isEmpty)
                    #expect(resp.stopReason == "end_turn")
                }
            }
        }
    }

    @Test("response content contains mock text")
    func responseContentContainsMockText() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(mockConverseResponse()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicResponse.self) {
                    let texts = resp.content.compactMap(\.text)
                    #expect(texts.contains("Hello from mock"))
                }
            }
        }
    }

    @Test("throttling error returns 429")
    func throttlingErrorReturns429() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .failure(mockThrottlingError))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .tooManyRequests)
            }
        }
    }

    @Test("tool_use response has stop_reason tool_use")
    func toolUseResponseHasToolUseStopReason() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(toolUseConverseResponse()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicResponse.self) {
                    #expect(resp.stopReason == "tool_use")
                }
            }
        }
    }

    @Test("tool_use response content includes text and tool_use blocks")
    func toolUseResponseContentIncludesTextAndToolUseBlocks() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(toolUseConverseResponse()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicResponse.self) {
                    let types = resp.content.map(\.type)
                    #expect(types.contains("text"))
                    #expect(types.contains("tool_use"))
                }
            }
        }
    }

    @Test("tool_use block has correct id name and input")
    func toolUseBlockHasCorrectIdNameAndInput() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .success(toolUseConverseResponse()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: validBody)) { res async in
                #expect(res.status == .ok)
                if let resp = try? res.content.decode(AnthropicResponse.self),
                   let toolBlock = resp.content.first(where: { $0.type == "tool_use" }) {
                    #expect(toolBlock.id == "tooluse_abc123")
                    #expect(toolBlock.name == "XcodeRead")
                    #expect(toolBlock.input == .object(["filePath": .string("src/main.swift")]))
                }
            }
        }
    }
}

// MARK: - Streaming Tests

@Suite("MessagesController streaming")
struct MessagesControllerStreamingTests {

    private let streamingBody = """
    {"model":"claude-sonnet","messages":[{"role":"user","content":"Hello"}],"max_tokens":100,"stream":true}
    """

    @Test("returns OK with SSE content type")
    func returnsOKWithSSEContentType() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(minimalStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                #expect(res.status == .ok)
                #expect(res.headers.first(name: .contentType)?.contains("text/event-stream") == true)
            }
        }
    }

    @Test("SSE body contains message_start event")
    func sseBodyContainsMessageStart() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(minimalStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                let bodyStr = res.body.string
                #expect(bodyStr.contains("event: message_start"))
            }
        }
    }

    @Test("SSE body contains ping event")
    func sseBodyContainsPing() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(minimalStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                let bodyStr = res.body.string
                #expect(bodyStr.contains("event: ping"))
            }
        }
    }

    @Test("SSE body contains message_stop event")
    func sseBodyContainsMessageStop() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(minimalStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                let bodyStr = res.body.string
                #expect(bodyStr.contains("event: message_stop"))
            }
        }
    }

    @Test("throttling error during setup returns 429")
    func throttlingErrorDuringSetupReturns429() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .failure(mockThrottlingError))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                #expect(res.status == .tooManyRequests)
            }
        }
    }

    @Test("tool_use stream emits content_block_start with type tool_use")
    func toolUseStreamEmitsContentBlockStart() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(toolUseStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                let body = res.body.string
                #expect(body.contains("content_block_start"))
                #expect(body.contains("\"type\":\"tool_use\""))
                #expect(body.contains("\"id\":\"tooluse_abc123\""))
                #expect(body.contains("\"name\":\"XcodeRead\""))
            }
        }
    }

    @Test("tool_use stream emits input_json_delta")
    func toolUseStreamEmitsInputJsonDelta() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(toolUseStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                let body = res.body.string
                #expect(body.contains("content_block_delta"))
                #expect(body.contains("input_json_delta"))
            }
        }
    }

    @Test("tool_use stream emits message_delta with stop_reason tool_use")
    func toolUseStreamEmitsToolUseStopReason() async throws {
        try await withApp({ app in
            try configureMessagesApp(app: app, behavior: .streamSuccess(toolUseStreamEvents()))
        }) { app in
            var headers = HTTPHeaders()
            headers.contentType = .json

            try await app.test(.POST, "/v1/messages", headers: headers, body: ByteBuffer(string: streamingBody)) { res async in
                let body = res.body.string
                #expect(body.contains("message_delta"))
                #expect(body.contains("\"stop_reason\":\"tool_use\""))
            }
        }
    }
}
