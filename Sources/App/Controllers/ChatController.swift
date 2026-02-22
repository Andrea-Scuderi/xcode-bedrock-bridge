import Vapor
import Foundation
import SotoBedrockRuntime

struct ChatController: RouteCollection {
    let bedrockService: BedrockService
    let modelMapper: ModelMapper
    let requestTranslator: RequestTranslator
    let responseTranslator: ResponseTranslator

    func boot(routes: RoutesBuilder) throws {
        routes.post("v1", "chat", "completions", use: chatCompletions)
    }

    @Sendable
    func chatCompletions(req: Request) async throws -> Response {
        if let bodyString = req.body.string {
            req.logger.debug("Xcode payload: \(bodyString)")
        }

        let chatRequest = try req.content.decode(ChatCompletionRequest.self)
        let modelID = modelMapper.bedrockModelID(for: chatRequest.model)
        let completionID = "chatcmpl-\(UUID().uuidString)"

        let (system, messages, inferenceConfig) = requestTranslator.translate(
            request: chatRequest,
            modelID: modelID
        )

        if chatRequest.stream == true {
            return try await handleStreaming(
                req: req,
                chatRequest: chatRequest,
                modelID: modelID,
                completionID: completionID,
                system: system,
                messages: messages,
                inferenceConfig: inferenceConfig
            )
        } else {
            return try await handleNonStreaming(
                req: req,
                chatRequest: chatRequest,
                modelID: modelID,
                completionID: completionID,
                system: system,
                messages: messages,
                inferenceConfig: inferenceConfig
            )
        }
    }

    // MARK: - Non-streaming

    private func handleNonStreaming(
        req: Request,
        chatRequest: ChatCompletionRequest,
        modelID: String,
        completionID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration
    ) async throws -> Response {
        do {
            let bedrockResponse = try await bedrockService.converse(
                modelID: modelID,
                system: system,
                messages: messages,
                inferenceConfig: inferenceConfig
            )
            let openAIResponse = responseTranslator.translate(
                response: bedrockResponse,
                model: chatRequest.model,
                completionID: completionID
            )
            return try await openAIResponse.encodeResponse(for: req)
        } catch {
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: String(describing: error))
        }
    }

    // MARK: - Streaming

    private func handleStreaming(
        req: Request,
        chatRequest: ChatCompletionRequest,
        modelID: String,
        completionID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration
    ) async throws -> Response {
        // Perform the Bedrock handshake before opening the SSE response so that
        // access / auth errors are returned as proper HTTP error codes rather
        // than being buried inside a 200 OK SSE body.
        let textStream: AsyncThrowingStream<String, Error>
        do {
            textStream = try await bedrockService.converseStream(
                modelID: modelID,
                system: system,
                messages: messages,
                inferenceConfig: inferenceConfig
            )
        } catch {
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: String(describing: error))
        }

        let model = chatRequest.model
        let encoder = JSONEncoder()
        let translator = responseTranslator

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")

        response.body = .init(stream: { writer in
            Task {
                func send(_ chunk: some Encodable) {
                    guard let data = try? encoder.encode(chunk),
                          let jsonStr = String(data: data, encoding: .utf8) else { return }
                    writer.write(.buffer(ByteBuffer(string: "data: \(jsonStr)\n\n")))
                }

                do {
                    // Initial role chunk
                    let roleChunk = ChatCompletionChunk(
                        id: completionID,
                        object: "chat.completion.chunk",
                        created: Int(Date().timeIntervalSince1970),
                        model: model,
                        choices: [ChunkChoice(
                            index: 0,
                            delta: ChunkDelta(role: "assistant", content: nil),
                            finishReason: nil
                        )]
                    )
                    send(roleChunk)

                    for try await text in textStream {
                        let chunk = translator.streamChunk(
                            text: text,
                            model: model,
                            completionID: completionID
                        )
                        send(chunk)
                    }

                    // Stop chunk
                    let stopChunk = translator.stopChunk(
                        model: model,
                        completionID: completionID,
                        stopReason: nil
                    )
                    send(stopChunk)

                    writer.write(.buffer(ByteBuffer(string: "data: [DONE]\n\n")))
                    writer.write(.end)
                } catch {
                    // Use String(describing:) so Soto errors report their real
                    // error code + message instead of the opaque NSError bridge.
                    let errorMsg = String(describing: error)
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: " ")
                    writer.write(.buffer(ByteBuffer(
                        string: "event: error\ndata: {\"error\":\"\(errorMsg)\"}\n\n"
                    )))
                    writer.write(.end)
                }
            }
        })

        return response
    }
}
