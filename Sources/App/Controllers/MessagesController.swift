import Vapor
import Foundation
import SotoBedrockRuntime

// MARK: - Input guardrail limits

private let maxMessages        = 100
private let maxModelNameLength = 128
private let maxToolCount       = 50
private let maxToolNameLength  = 64
private let maxSystemTextLength   = 32_768   // chars (~32k tokens)
private let maxMessageTextLength  = 65_536   // chars per content block

struct MessagesController: RouteCollection {
    let bedrockService: any BedrockConversable
    let modelMapper: ModelMapper
    let requestTranslator: AnthropicRequestTranslator
    let responseTranslator: AnthropicResponseTranslator

    func boot(routes: RoutesBuilder) throws {
        routes.post("v1", "messages", use: messages)
        routes.post("v1", "messages", "count_tokens", use: countTokens)
    }

    // MARK: - POST /v1/messages

    @Sendable
    func messages(req: Request) async throws -> Response {
        let request = try req.content.decode(AnthropicRequest.self)

        if let body = req.body.string {
            req.logger.debug("Xcode /v1/messages payload: \(body)")
        }

        guard request.model.count <= maxModelNameLength else {
            throw Abort(.badRequest, reason: "Model name too long (max \(maxModelNameLength) chars).")
        }

        guard request.messages.count <= maxMessages else {
            throw Abort(.badRequest, reason: "Too many messages (max \(maxMessages)).")
        }

        if let tools = request.tools, !tools.isEmpty {
            guard tools.count <= maxToolCount else {
                throw Abort(.badRequest, reason: "Too many tools (max \(maxToolCount)).")
            }
            for tool in tools {
                guard tool.name.count <= maxToolNameLength else {
                    throw Abort(.badRequest, reason: "Tool name too long (max \(maxToolNameLength) chars).")
                }
            }
        }

        if let system = request.system {
            guard system.plainText.count <= maxSystemTextLength else {
                throw Abort(.badRequest, reason: "System prompt exceeds maximum allowed length of \(maxSystemTextLength) chars.")
            }
        }

        for msg in request.messages {
            for block in msg.content.blocks {
                if let text = block.text {
                    guard text.count <= maxMessageTextLength else {
                        throw Abort(.badRequest, reason: "Message content exceeds maximum allowed length of \(maxMessageTextLength) chars.")
                    }
                }
            }
        }

        let modelID = modelMapper.bedrockModelID(for: request.model)
        req.logger.debug("bedrockModelID: \(request.model) → \(modelID)")
        let messageID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        let (system, msgs, inferenceConfig, toolConfig) = try requestTranslator.translate(request: request, resolvedModelID: modelID)

        if request.stream == true {
            return try await handleStreaming(
                req: req, request: request, modelID: modelID, messageID: messageID,
                system: system, messages: msgs, inferenceConfig: inferenceConfig, toolConfig: toolConfig
            )
        } else {
            return try await handleNonStreaming(
                req: req, request: request, modelID: modelID, messageID: messageID,
                system: system, messages: msgs, inferenceConfig: inferenceConfig, toolConfig: toolConfig
            )
        }
    }

    // MARK: - POST /v1/messages/count_tokens

    @Sendable
    func countTokens(req: Request) async throws -> AnthropicCountTokensResponse {
        let request = try req.content.decode(AnthropicCountTokensRequest.self)
        // Bedrock has no count_tokens API. Estimate at ~4 chars per token.
        var charCount = request.system.map { $0.plainText.count } ?? 0
        for msg in request.messages {
            for block in msg.content.blocks {
                charCount += block.text?.count ?? 0
                charCount += block.input.map { "\($0)".count } ?? 0
            }
        }
        for tool in request.tools ?? [] {
            charCount += tool.name.count + (tool.description?.count ?? 0) + "\(tool.inputSchema)".count
        }
        return AnthropicCountTokensResponse(inputTokens: max(1, charCount / 4))
    }

    // MARK: - Non-streaming

    private func handleNonStreaming(
        req: Request,
        request: AnthropicRequest,
        modelID: String,
        messageID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> Response {
        do {
            let bedrockResponse = try await bedrockService.converse(
                modelID: modelID, system: system, messages: messages,
                inferenceConfig: inferenceConfig, toolConfig: toolConfig
            )
            let anthropicResponse = responseTranslator.translate(
                response: bedrockResponse, model: request.model, messageID: messageID
            )
            return try await anthropicResponse.encodeResponse(for: req)
        } catch {
            req.logger.error("Bedrock error: \(error)")
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: BedrockService.clientSafeReason(for: error))
        }
    }

    // MARK: - Streaming

    private func handleStreaming(
        req: Request,
        request: AnthropicRequest,
        modelID: String,
        messageID: String,
        system: [BedrockRuntime.SystemContentBlock],
        messages: [BedrockRuntime.Message],
        inferenceConfig: BedrockRuntime.InferenceConfiguration,
        toolConfig: BedrockRuntime.ToolConfiguration?
    ) async throws -> Response {
        // Start Bedrock handshake before committing to 200 OK.
        let rawStream: AsyncThrowingStream<BedrockRuntime.ConverseStreamOutput, Error>
        do {
            rawStream = try await bedrockService.converseStreamRaw(
                modelID: modelID, system: system, messages: messages,
                inferenceConfig: inferenceConfig, toolConfig: toolConfig
            )
        } catch {
            req.logger.error("Bedrock error: \(error)")
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: BedrockService.clientSafeReason(for: error))
        }

        let model = request.model
        let translator = responseTranslator
        let logger = req.logger

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")

        response.body = .init(asyncStream: { writer in
            do {
                let messageStartSSE = translator.messageStartSSE(messageID: messageID, model: model)
                logger.debug("Streaming messageStart")
                try await writer.writeBuffer(ByteBuffer(string: messageStartSSE))

                let pingSSE = translator.pingSSE()
                logger.debug("Streaming ping")
                try await writer.writeBuffer(ByteBuffer(string: pingSSE))

                var stopReason = "end_turn"
                var outputTokens = 0

                for try await event in rawStream {
                    switch event {
                    case .messageStop(let e):
                        stopReason = translator.translateStopReason(e.stopReason)
                    case .metadata(let e):
                        outputTokens = e.usage.outputTokens
                    default:
                        for sseStr in translator.translateStreamEvent(event) where !sseStr.isEmpty {
                            logger.debug("Streaming SSE: \(sseStr)")
                            try await writer.writeBuffer(ByteBuffer(string: sseStr))
                        }
                    }
                }

                let finalSSE = translator.finalSSE(stopReason: stopReason, outputTokens: outputTokens)
                logger.debug("Streaming finalSSE stopReason=\(stopReason) outputTokens=\(outputTokens)")
                try await writer.writeBuffer(ByteBuffer(string: finalSSE))
            } catch {
                logger.error("Bedrock streaming error: \(error)")
                let safeMsg = BedrockService.clientSafeReason(for: error)
                let errorSSE = "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"\(safeMsg)\"}}\n\n"
                try? await writer.writeBuffer(ByteBuffer(string: errorSSE))
            }
            try? await writer.write(.end)
        })

        return response
    }
}
