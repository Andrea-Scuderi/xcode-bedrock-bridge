# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`xcode-bedrock-bridge` is a local Vapor HTTP proxy server that connects Xcode 26.3 AI features to Amazon Bedrock Claude models. It translates between two client-facing protocols (OpenAI and Anthropic) and the AWS Bedrock Converse API, handling SigV4 authentication transparently.

**Status:** Work in Progress — Xcode 26.3 is in beta and the integration points may change.

## Common Commands

```bash
# Build release binary
swift build -c release

# Run the proxy server
swift run -c release Run

# Run with debug logging
LOG_LEVEL=debug swift run Run

# Run all tests
swift test

# Run a single test (by name)
swift test --filter "RouteTests/testModelsList"
```

## Architecture

```
Xcode Intelligence (OpenAI format)
         │
         ▼
POST /v1/chat/completions  ──►  ChatController
                                     │
                                     ├── RequestTranslator (OpenAI → Bedrock)
                                     ├── BedrockService (actor)
                                     └── ResponseTranslator (Bedrock → OpenAI)

Xcode Coding Agent (Anthropic format)
         │
         ▼
POST /v1/messages          ──►  MessagesController
                                     │
                                     ├── AnthropicRequestTranslator (Anthropic → Bedrock)
                                     ├── BedrockService (actor)
                                     └── AnthropicResponseTranslator (Bedrock → Anthropic SSE)

GET /v1/models             ──►  ModelsController (live via listFoundationModels; fallback from modelNameToBedrockID)
```

**Key design decisions:**
- `BedrockService` is a Swift actor for thread-safe AWS client operations. It exposes four methods: `converse()` (non-streaming), `converseStream()` (for OpenAI SSE), `converseStreamRaw()` (for Anthropic SSE, preserving raw Bedrock events), and `listFoundationModels()` (management API, returns `[FoundationModelInfo]`).
- `BedrockService` holds both a `BedrockRuntime` client (inference, `SotoBedrockRuntime`) and a `Bedrock` client (management, `SotoBedrock`), sharing the same underlying `AWSClient`.
- `ModelsController` fetches the live model list from `listFoundationModels` when real AWS credentials are present, using `modelName` as the `id` field and `providerName` as `owned_by` (falling back to prefix derivation when absent). It falls back to `fallbackModelList()` — derived from `ModelMapper.modelNameToBedrockID` — when using a Bedrock API key, when no `BedrockService` is initialised (tests), or when the API call fails. The `FoundationModelListable` protocol enables mock injection in tests.
- `ModelMapper` resolves model strings in three tiers: (1) native Bedrock ID passthrough via provider prefix, (2) short alias via `mapping`, (3) human-readable name via `modelNameToBedrockID`. This supports the round-trip: `GET /v1/models` returns a name → Xcode sends the name back → `ModelMapper` resolves it to the correct Bedrock inference profile ID.
- `BedrockConversable` protocol (in `BedrockService.swift`) exposes `converse()` and `converseStreamRaw()` — the two inference methods used by `MessagesController`. `MessagesController` stores `any BedrockConversable`, enabling mock injection in tests. `BedrockService` conforms to both `FoundationModelListable` and `BedrockConversable`.
- The Anthropic `/v1/messages` routes bypass `APIKeyMiddleware` because Xcode Coding Agent manages its own authentication.
- Bedrock requires strict user/assistant turn alternation — `RequestTranslator` handles merging/reordering as needed.
- Model aliases (e.g., `gpt-4`, `claude-sonnet-4-5`, `nova-pro`) are resolved to full Bedrock cross-region inference profile IDs in `ModelMapper`.

## Source Layout

| Path | Purpose |
|---|---|
| `Sources/App/configure.swift` | App bootstrap — initializes `BedrockService`, sets 32MB body limit |
| `Sources/App/routes.swift` | Route registration, applies `APIKeyMiddleware` selectively |
| `Sources/App/Controllers/` | HTTP endpoint handlers (Chat, Messages, Models) |
| `Sources/App/Services/BedrockService.swift` | Actor wrapping Soto's `BedrockRuntime` (inference) and `Bedrock` (management) clients; defines `FoundationModelListable` and `BedrockConversable` protocols |
| `Sources/App/Services/Configuration.swift` | `AppConfiguration` (env vars) and `ModelMapper` (alias resolution) |
| `Sources/App/Translation/` | Protocol converters between OpenAI, Anthropic, and Bedrock formats |
| `Sources/App/Models/` | Codable structs for OpenAI and Anthropic wire formats |
| `Sources/App/Middleware/APIKeyMiddleware.swift` | Optional `x-api-key` / `Authorization: Bearer` validation |

## Configuration

Configuration is loaded in priority order: process env vars > `.env` (dotenv) > `config.json`
(nested JSON). Both files are optional and gitignored.

| Variable | Default | Description |
|---|---|---|
| `AWS_REGION` | `us-east-1` | Bedrock region |
| `PROFILE` | — | AWS profile from `~/.aws/credentials` |
| `BEDROCK_API_KEY` | — | Bedrock API key (alternative to AWS credentials) |
| `DEFAULT_BEDROCK_MODEL` | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Fallback model when none specified |
| `PROXY_API_KEY` | — | Optional auth key for OpenAI endpoints |
| `PORT` | `8080` | HTTP listen port |
| `LOG_LEVEL` | `info` | Vapor log level (`debug` logs full request/response payloads) |

## Key Dependencies

- **Vapor** (≥4.115.0) — HTTP server framework
- **Soto / SotoBedrockRuntime + SotoBedrock** (≥7.0.0) — AWS SDK for Swift; `SotoBedrockRuntime` for inference (`converse`, `converseStream`); `SotoBedrock` for the management plane (`listFoundationModels`)

---

## Best Practices

### Swift Testing (preferred over XCTest)

Prefer the **Swift Testing** framework (`import Testing`) for all new tests. Use `VaporTesting` (not `XCTVapor`) for HTTP integration tests.

```swift
// Preferred — Swift Testing
import Testing
import VaporTesting
@testable import App

@Suite("ModelsController")
struct ModelsControllerTests {
    @Test("returns 200 without auth")
    func returnsOKWithoutAuth() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())
        try await app.test(.GET, "/v1/models") { res async in
            #expect(res.status == .ok)
        }
    }
}
```

- Use `#expect(...)` instead of `XCTAssertEqual` / `XCTAssertTrue`
- Use `#require(...)` when a nil or thrown value should abort the test immediately
- Use `@Suite` to group related tests (replaces `XCTestCase` subclasses)
- Use `@Test("description")` on each test function (no `test` prefix required)
- Parameterize with `@Test(arguments:)` instead of looping inside a single test

### Test File Structure

Test files **must mirror the `Sources/App` folder structure**, with **one file per suite**:

```
Tests/AppTests/
├── Controllers/
│   ├── ModelsControllerTests.swift       ← @Suite("ModelsController")
│   └── MessagesControllerTests.swift     ← @Suite("MessagesController ...")
├── Middleware/
│   └── APIKeyMiddlewareTests.swift       ← @Suite("APIKeyMiddleware")
├── Models/
│   ├── JSONValueCodingTests.swift        ← @Suite("JSONValue Coding")
│   ├── JSONValueAWSDocumentTests.swift   ← @Suite("JSONValue AWSDocument Conversion")
│   ├── AnthropicMessageContentTests.swift
│   ├── AnthropicSystemTests.swift
│   ├── AnthropicToolResultContentTests.swift
│   └── ChatMessageTests.swift
├── Services/
│   ├── ModelMapperTests.swift            ← @Suite("ModelMapper")
│   ├── AppConfigurationTests.swift       ← @Suite("AppConfiguration Defaults")
│   └── BedrockServiceTests.swift         ← @Suite("BedrockService Error Mapping")
└── Translation/
    ├── RequestTranslatorTests.swift
    ├── ResponseTranslatorTests.swift
    ├── AnthropicRequestTranslatorTests.swift
    └── AnthropicResponseTranslatorTests.swift
```

Rules:
- Each `@Suite` lives in its own `.swift` file — never combine multiple suites in one file.
- The subdirectory matches the `Sources/App` subdirectory where the type under test lives.
- File name = `<TypeUnderTest>Tests.swift` (e.g., `ModelMapper` → `ModelMapperTests.swift`).

To run a Swift Testing test by name:
```bash
swift test --filter "ModelsControllerTests/returnsOKWithoutAuth"
swift test --filter "ModelMapperTests"
```

### Swift Concurrency

- Use **actors** for any type that owns shared mutable state or wraps a non-Sendable client (see `BedrockService`). Avoid `DispatchQueue` or locks.
- Mark all value types (`struct`, `enum`) that cross concurrency boundaries as `Sendable`. For types with only `Sendable` stored properties this is synthesized automatically; add it explicitly to make the intent clear.
- Use `nonisolated` on actor methods that do not access isolated state — particularly methods that immediately launch a `Task` or return an `AsyncThrowingStream`. This avoids an unnecessary hop onto the actor's executor before real work starts.
- Wrap callback- or event-based async APIs in `AsyncThrowingStream` with a `continuation`. Always call `continuation.finish()` (or `continuation.finish(throwing:)`) in every exit path.
- Prefer **structured concurrency** (`async let`, `withTaskGroup`) over detached `Task { }` when results are needed in the same scope. Use `Task { }` only to bridge into a non-async context (e.g., inside a Vapor `Response.Body` stream closure).
- Avoid `Task.detached` unless you explicitly need to opt out of task-local values and actor context.
- Do not use `@MainActor` in server-side code — there is no main actor run loop in a Vapor server process.

### Vapor

- Implement every controller as a `struct` conforming to `RouteCollection`; register routes in `boot(routes:)`.
- All route handler functions must be `@Sendable` and `async throws`. Return `Response` directly for full control (status, headers, body), or return a `Content`-conforming type and let Vapor encode it.
- Use `req.content.decode(T.self)` for request bodies and `.encodeResponse(for: req)` for typed responses.
- For **streaming responses** (SSE), build a `Response` with a `.init(stream: { writer in ... })` body and set the required headers before returning:
  ```swift
  response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
  response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
  response.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")
  ```
  Write chunks with `writer.write(.buffer(...))` and close with `writer.write(.end)`.
- Extend `Application` with a custom `StorageKey` type for each injected service (see `BedrockServiceKey` in `Configuration.swift`). Never store services as global variables.
- Throw `Abort(.httpStatus, reason: "...")` for all HTTP-layer errors. Map domain-specific errors to HTTP status codes in a single helper (see `BedrockService.httpStatus(for:)`), not scattered across controllers.
- For **middleware**, implement `AsyncMiddleware` (not the synchronous `Middleware`). Keep middleware stateless; pass any required configuration through the initializer.
- Avoid blocking calls (file I/O, `Thread.sleep`, synchronous network) inside route handlers or middleware — everything must remain non-blocking.

### Server-Side Swift

- The project targets **Swift 6** with macOS 15+. Treat all concurrency warnings as errors; do not suppress them with `@preconcurrency` without a clear justification.
- Prefer value types (`struct`) over reference types (`class`) for models, translators, and configuration. Use `class` only when reference semantics or inheritance is genuinely required.
- `Codable` types used as HTTP bodies should also conform to `Content` (Vapor's protocol) or be decoded explicitly via `req.content.decode`.
- Keep the `Run` target minimal — only the `@main` entry point. All logic lives in the `App` library target so it can be tested without starting a live server.
- Log with Vapor's `req.logger` (or `app.logger`) rather than `print`. Use structured metadata for request-scoped context.
