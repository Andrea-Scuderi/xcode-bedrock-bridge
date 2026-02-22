import Vapor
import SotoCore
import SotoBedrockRuntime

actor BedrockService {
    private let client: AWSClient
    let runtime: BedrockRuntime

    init(region: String, profile: String? = nil) {
        let credentialProvider: CredentialProviderFactory = profile.map {
            .configFile(profile: $0)
        } ?? .default
        self.client = AWSClient(credentialProvider: credentialProvider)
        self.runtime = BedrockRuntime(client: client, region: .init(rawValue: region))
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
        inferenceConfig: BedrockRuntime.InferenceConfiguration
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
                        case .messageStop:
                            continuation.finish()
                            return
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
}

// MARK: - Error Mapping

extension BedrockService {
    static func httpStatus(for error: Error) -> HTTPResponseStatus {
        let description = String(describing: type(of: error))
        if description.contains("Throttling") || description.contains("throttling") {
            return .tooManyRequests
        } else if description.contains("Validation") || description.contains("validation") {
            return .badRequest
        } else if description.contains("AccessDenied") || description.contains("accessDenied") {
            return .unauthorized
        } else if description.contains("ResourceNotFound") || description.contains("ModelNotFound") {
            return .notFound
        } else if description.contains("ServiceUnavailable") || description.contains("serviceUnavailable") {
            return .serviceUnavailable
        }
        return .internalServerError
    }
}
