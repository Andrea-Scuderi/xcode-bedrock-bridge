import Vapor
import SotoCore

// MARK: - JSONValue
// Sendable recursive JSON type used for tool inputs/outputs.

enum JSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil()                           { self = .null;             return }
        if let v = try? c.decode(Bool.self)        { self = .bool(v);          return }
        if let v = try? c.decode(Int.self)         { self = .number(Double(v)); return }
        if let v = try? c.decode(Double.self)      { self = .number(v);        return }
        if let v = try? c.decode(String.self)      { self = .string(v);        return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v);         return }
        self = .object(try c.decode([String: JSONValue].self))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null:          try c.encodeNil()
        case .bool(let v):   try c.encode(v)
        case .number(let v):
            if v.truncatingRemainder(dividingBy: 1) == 0, let i = Int(exactly: v) {
                try c.encode(i)
            } else {
                try c.encode(v)
            }
        case .string(let v): try c.encode(v)
        case .array(let v):  try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

extension JSONValue {
    func toAWSDocument() -> AWSDocument {
        switch self {
        case .null:          return .null
        case .bool(let v):   return .boolean(v)
        case .number(let v):
            if v.truncatingRemainder(dividingBy: 1) == 0, let i = Int(exactly: v) {
                return .integer(i)
            }
            return .double(v)
        case .string(let v): return .string(v)
        case .array(let v):  return .array(v.map { $0.toAWSDocument() })
        case .object(let v): return .map(v.mapValues { $0.toAWSDocument() })
        }
    }

    static func from(document: AWSDocument) -> JSONValue {
        switch document {
        case .null:            return .null
        case .boolean(let v):  return .bool(v)
        case .double(let v):   return .number(v)
        case .integer(let v):  return .number(Double(v))
        case .string(let v):   return .string(v)
        case .array(let v):    return .array(v.map { from(document: $0) })
        case .map(let v):      return .object(v.mapValues { from(document: $0) })
        }
    }
}

// MARK: - Content Blocks

/// tool_result.content can be a plain string or an array of text blocks.
enum AnthropicToolResultContent: Codable, Sendable {
    case text(String)
    case blocks([AnthropicContentBlock])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let t = try? c.decode(String.self) { self = .text(t); return }
        self = .blocks(try c.decode([AnthropicContentBlock].self))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let v):   try c.encode(v)
        case .blocks(let v): try c.encode(v)
        }
    }

    var asText: String {
        switch self {
        case .text(let t):   return t
        case .blocks(let bs): return bs.compactMap(\.text).joined()
        }
    }
}

struct AnthropicContentBlock: Codable, Sendable {
    let type: String
    // text
    let text: String?
    // tool_use
    let id: String?
    let name: String?
    let input: JSONValue?
    // tool_result
    let toolUseId: String?
    let content: AnthropicToolResultContent?

    enum CodingKeys: String, CodingKey {
        case type, text, id, name, input, content
        case toolUseId = "tool_use_id"
    }

    static func text(_ text: String) -> AnthropicContentBlock {
        .init(type: "text", text: text, id: nil, name: nil, input: nil, toolUseId: nil, content: nil)
    }

    static func toolUse(id: String, name: String, input: JSONValue) -> AnthropicContentBlock {
        .init(type: "tool_use", text: nil, id: id, name: name, input: input, toolUseId: nil, content: nil)
    }
}

// MARK: - Message Content (string or array of blocks)

enum AnthropicMessageContent: Codable, Sendable {
    case text(String)
    case blocks([AnthropicContentBlock])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let t = try? c.decode(String.self) { self = .text(t); return }
        self = .blocks(try c.decode([AnthropicContentBlock].self))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let v):   try c.encode(v)
        case .blocks(let v): try c.encode(v)
        }
    }

    var blocks: [AnthropicContentBlock] {
        switch self {
        case .text(let t):   return [.text(t)]
        case .blocks(let bs): return bs
        }
    }
}

// MARK: - System (string or array of text blocks)

struct AnthropicTextBlock: Codable, Sendable {
    let type: String
    let text: String
}

enum AnthropicSystem: Codable, Sendable {
    case text(String)
    case blocks([AnthropicTextBlock])

    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let t = try? c.decode(String.self) { self = .text(t); return }
        self = .blocks(try c.decode([AnthropicTextBlock].self))
    }

    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let v):   try c.encode(v)
        case .blocks(let v): try c.encode(v)
        }
    }

    var plainText: String {
        switch self {
        case .text(let t):    return t
        case .blocks(let bs): return bs.map(\.text).joined(separator: "\n")
        }
    }
}

// MARK: - Tools

struct AnthropicTool: Codable, Sendable {
    let name: String
    let description: String?
    let inputSchema: JSONValue

    enum CodingKeys: String, CodingKey {
        case name, description
        case inputSchema = "input_schema"
    }
}

struct AnthropicToolChoice: Codable, Sendable {
    let type: String   // "auto" | "any" | "none" | "tool"
    let name: String?  // required when type == "tool"
}

// MARK: - Request / Response

struct AnthropicMessage: Codable, Sendable {
    let role: String
    let content: AnthropicMessageContent
}

struct AnthropicRequest: Content {
    let model: String
    let messages: [AnthropicMessage]
    let maxTokens: Int
    let system: AnthropicSystem?
    let tools: [AnthropicTool]?
    let toolChoice: AnthropicToolChoice?
    let stream: Bool?
    let temperature: Double?
    let topP: Double?
    let stopSequences: [String]?

    enum CodingKeys: String, CodingKey {
        case model, messages, system, tools, stream, temperature
        case maxTokens    = "max_tokens"
        case toolChoice   = "tool_choice"
        case topP         = "top_p"
        case stopSequences = "stop_sequences"
    }
}

struct AnthropicResponse: Content {
    let id: String
    let type: String       // "message"
    let role: String       // "assistant"
    let content: [AnthropicContentBlock]
    let model: String
    let stopReason: String?
    let usage: AnthropicUsage

    enum CodingKeys: String, CodingKey {
        case id, type, role, content, model, usage
        case stopReason = "stop_reason"
    }
}

struct AnthropicUsage: Codable, Sendable {
    let inputTokens: Int
    let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens  = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Count Tokens

struct AnthropicCountTokensRequest: Content {
    let model: String
    let messages: [AnthropicMessage]
    let system: AnthropicSystem?
    let tools: [AnthropicTool]?
}

struct AnthropicCountTokensResponse: Content {
    let inputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
    }
}
