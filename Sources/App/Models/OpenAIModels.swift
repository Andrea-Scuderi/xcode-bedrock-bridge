import Vapor

// MARK: - Chat Completion Request

struct ChatCompletionRequest: Content {
    let model: String
    let messages: [ChatMessage]
    let maxTokens: Int?
    let temperature: Double?
    let topP: Double?
    let stream: Bool?
    let stop: [String]?

    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream, stop
        case maxTokens = "max_tokens"
        case topP = "top_p"
    }
}

struct ChatMessage: Content {
    let role: String
    /// Normalised plain-text content, regardless of whether the sender
    /// sent a bare string or an array of content-part objects.
    let content: String

    // OpenAI spec allows content to be either a String or an array of
    // content-part objects: [{"type":"text","text":"..."}]
    // Xcode 26 uses the array form, so we accept both.
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)

        // Try plain string first, then fall back to content-part array.
        if let plain = try? container.decode(String.self, forKey: .content) {
            content = plain
        } else {
            let parts = try container.decode([ContentPart].self, forKey: .content)
            content = parts.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        }
    }

    private enum CodingKeys: String, CodingKey { case role, content }

    private struct ContentPart: Decodable {
        let type: String
        let text: String?
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
}

struct ChunkDelta: Content {
    let role: String?
    let content: String?
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
