import Vapor
import SotoCore
import SotoBedrockRuntime
import SotoBedrock

// MARK: - Protocol

protocol FoundationModelListable: Sendable {
    func listFoundationModels() async throws -> [FoundationModelInfo]
}

// MARK: - Actor

actor BedrockService {
    private let client: AWSClient
    let runtime: BedrockRuntime
    let bedrock: Bedrock

    init(region: String, profile: String? = nil, bedrockAPIKey: String? = nil) {
        if let apiKey = bedrockAPIKey {
            // Bedrock API key authentication: inject Bearer token; skip SigV4 (empty credentials
            // cause signHeaders to return early without adding an Authorization header).
            self.client = AWSClient(
                credentialProvider: .empty,
                middleware: AWSEditHeadersMiddleware(.replace(name: "Authorization", value: "Bearer \(apiKey)"))
            )
        } else {
            let credentialProvider: CredentialProviderFactory = profile.map {
                .configFile(profile: $0)
            } ?? .default
            self.client = AWSClient(credentialProvider: credentialProvider)
        }
        self.runtime = BedrockRuntime(client: client, region: .init(rawValue: region))
        self.bedrock = Bedrock(client: client, region: .init(rawValue: region))
    }

    deinit {
        try? client.syncShutdown()
    }

    // MARK: - Non-streaming

    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration? = nil
    ) async throws -> BedrockRuntime.ConverseResponse {
        let request = BedrockRuntime.ConverseRequest(
            inferenceConfig: inferenceConfig,
            messages: messages,
            modelId: modelID,
            system: system.isEmpty ? nil : system,
            toolConfig: toolConfig
        )
        return try await runtime.converse(request)
    }

    // MARK: - Streaming
    // nonisolated + async throws: the Bedrock handshake (runtime.converseStream) happens
    // here before we return the stream, so auth/access errors are thrown to the caller
    // while it can still send a proper HTTP error response rather than a 200 SSE body.
    // `runtime` is a `let`, safe to access from a nonisolated context.
    /// Streaming for the OpenAI `/v1/chat/completions` path — yields plain text deltas only.
    nonisolated func converseStream(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        onUsage: (@Sendable (_ inputTokens: Int, _ outputTokens: Int) -> Void)? = nil,
        onStop: (@Sendable (_ stopReason: BedrockRuntime.StopReason?) -> Void)? = nil
    ) async throws -> AsyncThrowingStream<String, Error> {
        let request = BedrockRuntime.ConverseStreamRequest(
            inferenceConfig: inferenceConfig,
            messages: messages,
            modelId: modelID,
            system: system.isEmpty ? nil : system
        )
        let response = try await runtime.converseStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // response.stream is AWSEventStream<ConverseStreamOutput> (non-optional)
                    for try await event in response.stream {
                        switch event {
                        case .contentBlockDelta(let deltaEvent):
                            switch deltaEvent.delta {
                            case .text(let text):
                                continuation.yield(text)
                            default:
                                break
                            }
                        case .metadata(let e):
                            onUsage?(e.usage.inputTokens, e.usage.outputTokens)
                        case .messageStop(let e):
                            onStop?(e.stopReason)
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Streaming for the Anthropic `/v1/messages` path — yields raw Bedrock events
    /// so the caller can translate them into Anthropic SSE format (including tool use).
    nonisolated func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration? = nil
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error> {
        let request = BedrockRuntime.ConverseStreamRequest(
            inferenceConfig: inferenceConfig,
            messages: messages,
            modelId: modelID,
            system: system.isEmpty ? nil : system,
            toolConfig: toolConfig
        )
        let response = try await runtime.converseStream(request)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await event in response.stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Foundation Models

    func listFoundationModels() async throws -> [FoundationModelInfo] {
        let input = Bedrock.ListFoundationModelsRequest(
            byInferenceType: .onDemand,
            byOutputModality: .text
        )
        let response = try await bedrock.listFoundationModels(input)
        return (response.modelSummaries ?? []).map { summary in
            FoundationModelInfo(
                modelId: summary.modelId,
                modelName: summary.modelName,
                providerName: summary.providerName,
                isActive: summary.modelLifecycle?.status == .active,
                inputModalities: summary.inputModalities?.map(\.rawValue) ?? [],
                outputModalities: summary.outputModalities?.map(\.rawValue) ?? [],
                responseStreamingSupported: summary.responseStreamingSupported,
                inferenceTypesSupported: summary.inferenceTypesSupported?.map(\.rawValue) ?? []
            )
        }
    }
}

// MARK: - FoundationModelListable Conformance

extension BedrockService: FoundationModelListable {}

// MARK: - BedrockConversable

protocol BedrockConversable: Sendable {
    func converse(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> BedrockRuntime.ConverseResponse

    func converseStreamRaw(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error>

    func converseStream(
        modelID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        onUsage: (@Sendable (_ inputTokens: Int, _ outputTokens: Int) -> Void)?,
        onStop: (@Sendable (_ stopReason: BedrockRuntime.StopReason?) -> Void)?
    ) async throws -> AsyncThrowingStream<String, Error>
}

// MARK: - BedrockConversable Conformance

extension BedrockService: BedrockConversable {}

// MARK: - Error Mapping

extension BedrockService {
    static func httpStatus(for error: Error) -> HTTPResponseStatus {
        if let awsError = error as? AWSErrorType {
            let code = awsError.errorCode.lowercased()
            if code.contains("throttling") { return .tooManyRequests }
            if code.contains("validation") { return .badRequest }
            if code.contains("accessdenied") { return .forbidden }
            if code.contains("resourcenotfound") || code.contains("modelnotfound") { return .notFound }
            if code.contains("serviceunavailable") { return .serviceUnavailable }
            // Fall back to the HTTP status from the AWS response context when available.
            if let responseCode = awsError.context?.responseCode { return responseCode }
        }
        return .internalServerError
    }

    /// Returns a client-safe error reason (HTTP status phrase only).
    /// Full error details are logged server-side; AWS internals are never sent to clients.
    static func clientSafeReason(for error: Error) -> String {
        httpStatus(for: error).reasonPhrase
    }
}
