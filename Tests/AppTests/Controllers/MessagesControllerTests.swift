import Testing
import VaporTesting
@testable import App

@Suite("MessagesController Token Counting")
struct MessagesControllerTests {

    private func makeApp() async throws -> Application {
        let app = try await Application.make(.testing)
        let bedrockService = BedrockService(region: "us-east-1", bedrockAPIKey: "fake-key")
        let controller = MessagesController(
            bedrockService: bedrockService,
            modelMapper: ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"),
            requestTranslator: AnthropicRequestTranslator(),
            responseTranslator: AnthropicResponseTranslator()
        )
        try app.register(collection: controller)
        return app
    }

    @Test("single 12-char message estimates 3 tokens")
    func countTokensSingleMessageEstimatesCorrectly() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

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

    @Test("2-char message returns minimum of 1 token")
    func countTokensShortMessageReturnsMinimumOne() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

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

    @Test("system prompt chars counted toward total")
    func countTokensSystemPromptCounts() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

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

    @Test("multiple messages chars aggregated")
    func countTokensMultipleMessagesAggregates() async throws {
        let app = try await makeApp()
        defer { Task { try await app.asyncShutdown() } }

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
