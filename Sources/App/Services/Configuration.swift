import Vapor

// MARK: - App Configuration

struct AppConfiguration: Sendable {
    let awsRegion: String
    let awsProfile: String?
    let bedrockAPIKey: String?
    let defaultBedrockModel: String
    let proxyAPIKey: String?
    let port: Int

    init() {
        awsRegion = Environment.get("AWS_REGION") ?? "us-east-1"
        awsProfile = Environment.get("PROFILE")
        bedrockAPIKey = Environment.get("BEDROCK_API_KEY")
        defaultBedrockModel = Environment.get("DEFAULT_BEDROCK_MODEL")
            ?? "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        proxyAPIKey = Environment.get("PROXY_API_KEY")
        port = Int(Environment.get("PORT") ?? "8080") ?? 8080
    }
}

// MARK: - Model Mapper

struct ModelMapper: Sendable {
    // All IDs use cross-region inference profiles (us. prefix) sourced directly
    // from https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html
    // and https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
    private static let mapping: [String: String] = [
        // GPT aliases
        "gpt-4":         "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "gpt-4o":        "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "gpt-4-turbo":   "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "gpt-3.5-turbo": "us.anthropic.claude-haiku-4-5-20251001-v1:0",

        // Claude 4.x
        "claude-sonnet-4-6":   "us.anthropic.claude-sonnet-4-6",
        "claude-sonnet-4-5":   "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "claude-sonnet-4":     "us.anthropic.claude-sonnet-4-20250514-v1:0",
        "claude-haiku-4-5":    "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        "claude-opus-4-6":     "us.anthropic.claude-opus-4-6-v1",
        "claude-opus-4-5":     "us.anthropic.claude-opus-4-5-20251101-v1:0",
        "claude-opus-4-1":     "us.anthropic.claude-opus-4-1-20250805-v1:0",

        // Claude 3.x
        "claude-3-7-sonnet":   "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
        "claude-3-5-sonnet-v2": "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
        "claude-3-5-sonnet":   "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
        "claude-3-5-haiku":    "us.anthropic.claude-3-5-haiku-20241022-v1:0",
        "claude-3-opus":       "us.anthropic.claude-3-opus-20240229-v1:0",
        "claude-3-sonnet":     "us.anthropic.claude-3-sonnet-20240229-v1:0",
        "claude-3-haiku":      "us.anthropic.claude-3-haiku-20240307-v1:0",
    ]

    let defaultModel: String

    func bedrockModelID(for openAIModel: String) -> String {
        // Pass through native Bedrock model IDs
        if openAIModel.contains("anthropic.") || openAIModel.contains("amazon.") {
            return openAIModel
        }
        return Self.mapping[openAIModel] ?? defaultModel
    }
}

// MARK: - Application Extension

extension Application {
    struct AppConfigKey: StorageKey {
        typealias Value = AppConfiguration
    }

    var appConfiguration: AppConfiguration {
        get {
            if let existing = storage[AppConfigKey.self] {
                return existing
            }
            let config = AppConfiguration()
            storage[AppConfigKey.self] = config
            return config
        }
        set {
            storage[AppConfigKey.self] = newValue
        }
    }

    struct BedrockServiceKey: StorageKey {
        typealias Value = BedrockService
    }

    var bedrockService: BedrockService {
        get {
            guard let service = storage[BedrockServiceKey.self] else {
                fatalError("BedrockService not initialized. Call configure(app:) first.")
            }
            return service
        }
        set {
            storage[BedrockServiceKey.self] = newValue
        }
    }
}
