import Vapor
import Foundation
import SotoBedrockRuntime

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

        let modelID = modelMapper.bedrockModelID(for: chatRequest.model)
        req.logger.debug("bedrockModelID: \(chatRequest.model) → \(modelID)")
        let completionID = "chatcmpl-\(UUID().uuidString)"

        let (system, messages, inferenceConfig) = try requestTranslator.translate(
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
        do {
            textStream = try await bedrockService.converseStream(
                modelID: modelID,
                system: system,
                messages: messages,
                inferenceConfig: inferenceConfig,
                onUsage: { input, output in
                    logger.info("tokens input=\(input) output=\(output)")
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
                        delta: ChunkDelta(role: "assistant", content: nil),
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
                    stopReason: nil
                )
                try await send(stopChunk)

                logger.debug("Streaming [DONE]")
                try await writer.writeBuffer(ByteBuffer(string: "data: [DONE]\n\n"))
                try await writer.write(.end)
            } catch {
                logger.error("Bedrock streaming error: \(error)")
                let safeMsg = BedrockService.clientSafeReason(for: error)
                let errorSSE = "event: error\ndata: {\"error\":\"\(safeMsg)\"}\n\n"
                try await writer.writeBuffer(ByteBuffer(string: errorSSE))
                try await writer.write(.end)
            }
        })

        return response
    }
}
