import Vapor
import Foundation
import SotoBedrockRuntime

/// Thread-safe box for the stop reason captured from the Bedrock stream.
/// Write happens (via onStop) before continuation.finish(); read happens after
/// the for-await loop exits — the structured concurrency ordering makes this safe.
private final class StopReasonBox: @unchecked Sendable {
    var value: BedrockRuntime.StopReason? = nil
}

// MARK: - Input guardrail limits

private let maxMessages          = 100
private let maxModelNameLength   = 128
private let maxMessageTextLength = 65_536   // chars per content block

struct ChatController: RouteCollection {
    let bedrockService: any BedrockConversable
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

        guard chatRequest.model.count <= maxModelNameLength else {
            throw Abort(.badRequest, reason: "Model name too long (max \(maxModelNameLength) chars).")
        }
        guard chatRequest.messages.count <= maxMessages else {
            throw Abort(.badRequest, reason: "Too many messages (max \(maxMessages)).")
        }
        for msg in chatRequest.messages {
            let text = msg.content.textOnly
            guard text.count <= maxMessageTextLength else {
                throw Abort(.badRequest, reason: "Message content exceeds maximum allowed length of \(maxMessageTextLength) chars.")
            }
        }
        if let n = chatRequest.n, n > 1 {
            throw Abort(.unprocessableEntity, reason: "Parameter 'n' > 1 is not supported. Only a single completion can be generated.")
        }
        if chatRequest.responseFormat?.type == "json_object" {
            throw Abort(.unprocessableEntity, reason: "response_format 'json_object' is not supported. The model cannot guarantee structured JSON output.")
        }
        if let tools = chatRequest.tools, !tools.isEmpty {
            throw Abort(.unprocessableEntity, reason: "The 'tools' parameter is not supported on the OpenAI-compatible endpoint. Use the Anthropic /v1/messages endpoint for tool use.")
        }

        let modelID = modelMapper.bedrockModelID(for: chatRequest.model)
        req.logger.info("bedrockModelID: \(chatRequest.model) → \(modelID)")
        let completionID = "chatcmpl-\(UUID().uuidString)"

        let (system, messages, inferenceConfig) = try requestTranslator.translate(
            request: chatRequest,
            modelID: modelID,
            modelMapper: modelMapper
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
                inferenceConfig: inferenceConfig,
                toolConfig: nil
            )
            let openAIResponse = responseTranslator.translate(
                response: bedrockResponse,
                model: chatRequest.model,
                completionID: completionID
            )
            req.logger.info("tokens input=\(openAIResponse.usage.promptTokens) output=\(openAIResponse.usage.completionTokens) total=\(openAIResponse.usage.totalTokens)")
            return try await openAIResponse.encodeResponse(for: req)
        } catch {
            req.logger.error("Bedrock error: \(error)")
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: BedrockService.clientSafeReason(for: error))
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
        let logger = req.logger
        let stopBox = StopReasonBox()
        do {
            textStream = try await bedrockService.converseStream(
                modelID: modelID,
                system: system,
                messages: messages,
                inferenceConfig: inferenceConfig,
                onUsage: { input, output in
                    logger.info("tokens input=\(input) output=\(output)")
                },
                onStop: { reason in
                    stopBox.value = reason
                }
            )
        } catch {
            logger.error("Bedrock error: \(error)")
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: BedrockService.clientSafeReason(for: error))
        }

        let model = chatRequest.model
        let encoder = JSONEncoder()
        let translator = responseTranslator

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")

        response.body = .init(asyncStream: { writer in
            func send(_ chunk: some Encodable) async throws {
                guard let data = try? encoder.encode(chunk),
                      let jsonStr = String(data: data, encoding: .utf8) else { return }
                let sseStr = "data: \(jsonStr)\n\n"
                logger.debug("Streaming SSE: \(sseStr)")
                try await writer.writeBuffer(ByteBuffer(string: sseStr))
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
                        delta: ChunkDelta(role: "assistant", content: ""),
                        finishReason: nil
                    )]
                )
                try await send(roleChunk)

                for try await text in textStream {
                    let chunk = translator.streamChunk(
                        text: text,
                        model: model,
                        completionID: completionID
                    )
                    try await send(chunk)
                }

                // Stop chunk
                let stopChunk = translator.stopChunk(
                    model: model,
                    completionID: completionID,
                    stopReason: stopBox.value
                )
                try await send(stopChunk)

                logger.debug("Streaming [DONE]")
                try await writer.writeBuffer(ByteBuffer(string: "data: [DONE]\n\n"))
                try await writer.write(.end)
            } catch {
                logger.error("Bedrock streaming error: \(error)")
                try await writer.write(.end)
            }
        })

        return response
    }
}
