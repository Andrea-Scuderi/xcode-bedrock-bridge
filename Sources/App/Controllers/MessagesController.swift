import Vapor
import Foundation
import SotoBedrockRuntime

struct MessagesController: RouteCollection {
    let bedrockService: BedrockService
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
        if let body = req.body.string {
            req.logger.debug("Xcode /v1/messages payload: \(body)")
        }

        let request = try req.content.decode(AnthropicRequest.self)
        let modelID = modelMapper.bedrockModelID(for: request.model)
        let messageID = "msg_\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"

        let (system, msgs, inferenceConfig, toolConfig) = requestTranslator.translate(request: request)

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
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: String(describing: error))
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
            let status = BedrockService.httpStatus(for: error)
            throw Abort(status, reason: String(describing: error))
        }

        let model = request.model
        let translator = responseTranslator

        let response = Response(status: .ok)
        response.headers.replaceOrAdd(name: .contentType, value: "text/event-stream")
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-cache")
        response.headers.replaceOrAdd(name: "X-Accel-Buffering", value: "no")

        response.body = .init(stream: { writer in
            Task {
                writer.write(.buffer(ByteBuffer(string: translator.messageStartSSE(messageID: messageID, model: model))))
                writer.write(.buffer(ByteBuffer(string: translator.pingSSE())))

                var stopReason = "end_turn"
                var outputTokens = 0

                do {
                    for try await event in rawStream {
                        switch event {
                        case .messageStop(let e):
                            stopReason = translator.translateStopReason(e.stopReason)
                        case .metadata(let e):
                            outputTokens = e.usage.outputTokens
                        default:
                            for sseStr in translator.translateStreamEvent(event) where !sseStr.isEmpty {
                                writer.write(.buffer(ByteBuffer(string: sseStr)))
                            }
                        }
                    }
                } catch {
                    let msg = String(describing: error)
                        .replacingOccurrences(of: "\\", with: "\\\\")
                        .replacingOccurrences(of: "\"", with: "\\\"")
                        .replacingOccurrences(of: "\n", with: " ")
                    writer.write(.buffer(ByteBuffer(string:
                        "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"api_error\",\"message\":\"\(msg)\"}}\n\n"
                    )))
                    writer.write(.end)
                    return
                }

                writer.write(.buffer(ByteBuffer(string: translator.finalSSE(stopReason: stopReason, outputTokens: outputTokens))))
                writer.write(.end)
            }
        })

        return response
    }
}
