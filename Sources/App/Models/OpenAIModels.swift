import Vapor

// MARK: - Image Translation Errors

enum ImageTranslationError: AbortError, Sendable {
    case unsupportedModel(String)
    case unsupportedFormat(String)
    case imageTooLarge(Int)       // estimated byte count

    var status: HTTPResponseStatus {
        switch self {
        case .unsupportedModel, .unsupportedFormat: return .unprocessableEntity   // 422
        case .imageTooLarge:                         return .payloadTooLarge        // 413
        }
    }
    var reason: String {
        switch self {
        case .unsupportedModel(let id):
            return "Model '\(id)' does not support image input."
        case .unsupportedFormat(let fmt):
            return "Unsupported image format '\(fmt)'. Allowed: jpeg, png, gif, webp."
        case .imageTooLarge(let bytes):
            return "Image (~\(bytes / 1024) KB estimated) exceeds the 3.75 MB Bedrock limit."
        }
    }
}

// MARK: - Image Types

struct ImageData: Sendable {
    let format: String      // "jpeg" | "png" | "gif" | "webp"
    let base64Data: String  // raw base64 string (after the comma in a data URL)
}

enum MessagePart: Sendable {
    case text(String)
    case image(ImageData)
}

enum MessageContent: Sendable {
    case text(String)
    case parts([MessagePart])

    var textOnly: String {
        switch self {
        case .text(let s): return s
        case .parts(let ps):
            return ps.compactMap { if case .text(let t) = $0 { return t } else { return nil } }.joined()
        }
    }

    var hasImages: Bool {
        if case .parts(let ps) = self {
            return ps.contains { if case .image = $0 { return true } else { return false } }
        }
        return false
    }

    var asParts: [MessagePart] {
        switch self {
        case .text(let s): return [.text(s)]
        case .parts(let ps): return ps
        }
    }
}

// MARK: - Data URL Parser

private func parseDataURL(_ url: String) -> ImageData? {
    guard url.hasPrefix("data:image/") else { return nil }
    let afterImage = String(url.dropFirst(11))  // drop "data:image/"
    guard let semiIdx = afterImage.firstIndex(of: ";") else { return nil }
    let format = String(afterImage[afterImage.startIndex..<semiIdx])
    let afterFmt = String(afterImage[semiIdx...].dropFirst())  // drop ";"
    guard afterFmt.hasPrefix("base64,") else { return nil }
    let base64Data = String(afterFmt.dropFirst(7))  // drop "base64,"
    guard !base64Data.isEmpty else { return nil }
    return ImageData(format: format, base64Data: base64Data)
}

// MARK: - Chat Completion Request helpers

struct ResponseFormat: Codable, Sendable {
    let type: String
}

// MARK: - Chat Completion Request

struct ChatCompletionRequest: Content {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?
    let stream: Bool?
    let stop: [String]?
    // Fields decoded but not forwarded to Bedrock
    let n: Int?
    let logprobs: Bool?
    let seed: Int?
    let user: String?
    let frequencyPenalty: Double?
    let presencePenalty: Double?
    let responseFormat: ResponseFormat?
    let tools: [JSONValue]?
    let toolChoice: JSONValue?

    /// Memberwise init — new optional params default to nil so existing call-sites don't break.
    init(
        model: String,
        messages: [ChatMessage],
        maxTokens: Int? = nil,
        temperature: Double? = nil,
        topP: Double? = nil,
        stream: Bool? = nil,
        stop: [String]? = nil,
        n: Int? = nil,
        logprobs: Bool? = nil,
        seed: Int? = nil,
        user: String? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil,
        responseFormat: ResponseFormat? = nil,
        tools: [JSONValue]? = nil,
        toolChoice: JSONValue? = nil
    ) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.stream = stream
        self.stop = stop
        self.n = n
        self.logprobs = logprobs
        self.seed = seed
        self.user = user
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.responseFormat = responseFormat
        self.tools = tools
        self.toolChoice = toolChoice
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model             = try c.decode(String.self,           forKey: .model)
        messages          = try c.decode([ChatMessage].self,    forKey: .messages)
        maxTokens         = try c.decodeIfPresent(Int.self,     forKey: .maxTokens)
        temperature       = try c.decodeIfPresent(Double.self,  forKey: .temperature)
        topP              = try c.decodeIfPresent(Double.self,  forKey: .topP)
        stream            = try c.decodeIfPresent(Bool.self,    forKey: .stream)
        stop              = try c.decodeIfPresent([String].self, forKey: .stop)
        n                 = try c.decodeIfPresent(Int.self,     forKey: .n)
        logprobs          = try c.decodeIfPresent(Bool.self,    forKey: .logprobs)
        seed              = try c.decodeIfPresent(Int.self,     forKey: .seed)
        user              = try c.decodeIfPresent(String.self,  forKey: .user)
        frequencyPenalty  = try c.decodeIfPresent(Double.self,  forKey: .frequencyPenalty)
        presencePenalty   = try c.decodeIfPresent(Double.self,  forKey: .presencePenalty)
        responseFormat    = try c.decodeIfPresent(ResponseFormat.self, forKey: .responseFormat)
        tools             = try c.decodeIfPresent([JSONValue].self, forKey: .tools)
        toolChoice        = try c.decodeIfPresent(JSONValue.self,   forKey: .toolChoice)
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, stop, n, logprobs, seed, user, tools
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case responseFormat = "response_format"
        case toolChoice = "tool_choice"
    }
}

struct ChatMessage: Content {
    let role: String
    /// Structured content — either a plain string or a list of parts (text + images).
    let content: MessageContent

    /// Convenience init for plain-text content (used throughout production code and tests).
    init(role: String, content: String) {
        self.role = role
        self.content = .text(content)
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)

        // Try plain string first, then fall back to content-part array.
        if let plain = try? container.decode(String.self, forKey: .content) {
            content = .text(plain)
        } else {
            let parts = try container.decode([ContentPart].self, forKey: .content)
            let messageParts: [MessagePart] = parts.compactMap { part in
                if part.type == "text", let text = part.text {
                    return .text(text)
                } else if part.type == "image_url",
                          let imageURL = part.imageURL,
                          let imageData = parseDataURL(imageURL.url) {
                    return .image(imageData)
                }
                return nil
            }
            content = .parts(messageParts)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        // Images are input-only; responses always carry plain text.
        try container.encode(content.textOnly, forKey: .content)
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    private struct ContentPart: Decodable {
        let type: String
        let text: String?
        let imageURL: ImageURLPart?

        enum CodingKeys: String, CodingKey {
            case type, text
            case imageURL = "image_url"
        }
    }

    private struct ImageURLPart: Decodable {
        let url: String
    }
}

// MARK: - Chat Completion Response (non-streaming)

struct ChatCompletionResponse: Content {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChatChoice]
    let usage: UsageInfo

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices, usage
    }
}

struct ChatChoice: Content {
    let index: Int
    let message: ChatMessage
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, message
        case finishReason = "finish_reason"
    }
}

struct UsageInfo: Content {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Streaming Chunk

struct ChatCompletionChunk: Content {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [ChunkChoice]

    enum CodingKeys: String, CodingKey {
        case id, object, created, model, choices
    }
}

struct ChunkChoice: Content {
    let index: Int
    let delta: ChunkDelta
    let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index, delta
        case finishReason = "finish_reason"
    }

    /// OpenAI spec requires `finish_reason` to always be present — `null` for
    /// intermediate chunks, a string value for the final stop chunk.
    /// Swift's synthesised encoder would omit the key when nil (`encodeIfPresent`),
    /// so we provide an explicit `encode(to:)` that writes `null` instead.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(delta, forKey: .delta)
        try container.encode(finishReason, forKey: .finishReason)
    }
}

struct ChunkDelta: Content {
    let role: String?
    let content: String?

    private enum CodingKeys: String, CodingKey { case role, content }

    /// `content` must always be present — `null` when absent (e.g. stop chunk) so
    /// that Xcode's parser never encounters a delta with no `content` key at all.
    /// `role` is still omitted when nil (only the initial role chunk carries it).
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encode(content, forKey: .content)
    }
}

// MARK: - Error Response

struct OpenAIErrorDetail: Content {
    let message: String
    let type: String
    let param: String?
    let code: String?
}

struct OpenAIErrorResponse: Content {
    let error: OpenAIErrorDetail
}

// MARK: - Models List

struct ModelListResponse: Content {
    let object: String
    let data: [ModelObject]
}

struct ModelObject: Content {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String

    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
    }
}
