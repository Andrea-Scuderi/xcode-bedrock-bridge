import Configuration
import Vapor

// MARK: - App Configuration

struct AppConfiguration: Sendable {
    let awsRegion: String
    let awsProfile: String?
    let bedrockAPIKey: String?
    let defaultBedrockModel: String
    let proxyAPIKey: String?
    let port: Int
    let bindHost: String
    let configuredModels: [FoundationModelInfo]?  // nil when models.json absent
    let crossRegionPrefix: String                 // e.g. "global", "us", "eu", "ap"

    init() {
        awsRegion = Environment.get("AWS_REGION") ?? "us-east-1"
        awsProfile = Environment.get("PROFILE")
        bedrockAPIKey = Environment.get("BEDROCK_API_KEY")
        defaultBedrockModel = Environment.get("DEFAULT_BEDROCK_MODEL")
            ?? "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        proxyAPIKey = Environment.get("PROXY_API_KEY")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        port = Int(Environment.get("PORT") ?? "8080") ?? 8080
        bindHost = Environment.get("BIND_HOST") ?? "127.0.0.1"
        configuredModels = nil
        crossRegionPrefix = Environment.get("CROSS_REGION_PREFIX") ?? "global"
    }

    /// Memberwise initializer — used in tests to inject specific values.
    init(
        awsRegion: String,
        awsProfile: String?,
        bedrockAPIKey: String?,
        defaultBedrockModel: String,
        proxyAPIKey: String?,
        port: Int,
        bindHost: String,
        configuredModels: [FoundationModelInfo]?,
        crossRegionPrefix: String = "global"
    ) {
        self.awsRegion = awsRegion
        self.awsProfile = awsProfile
        self.bedrockAPIKey = bedrockAPIKey
        self.defaultBedrockModel = defaultBedrockModel
        self.proxyAPIKey = proxyAPIKey
        self.port = port
        self.bindHost = bindHost
        self.configuredModels = configuredModels
        self.crossRegionPrefix = crossRegionPrefix
    }

    /// Reads all values from a pre-built ConfigReader.
    private init(reader: ConfigReader, configuredModels: [FoundationModelInfo]?) {
        awsRegion = reader.string(forKey: "aws.region") ?? "us-east-1"
        awsProfile = reader.string(forKey: "profile")
        bedrockAPIKey = reader.string(forKey: "bedrock.api.key")
        defaultBedrockModel = reader.string(forKey: "default.bedrock.model")
            ?? "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        proxyAPIKey = reader.string(forKey: "proxy.api.key")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        port = reader.int(forKey: "port") ?? 8080
        bindHost = reader.string(forKey: "bind.host") ?? "127.0.0.1"
        self.configuredModels = configuredModels
        crossRegionPrefix = reader.string(forKey: "cross.region.prefix") ?? "global"
    }

    /// Async factory — three-provider chain: process env > .env dotenv > config.json.
    /// Both files are optional; missing files are silently ignored.
    static func load() async throws -> AppConfiguration {
        let envProvider = EnvironmentVariablesProvider()
        let dotenvProvider = try await EnvironmentVariablesProvider(
            environmentFilePath: ".env",
            allowMissing: true
        )
        let jsonProvider = try await FileProvider<JSONSnapshot>(
            filePath: "config.json",
            allowMissing: true
        )
        let reader = ConfigReader(providers: [envProvider, dotenvProvider, jsonProvider])

        var configuredModels: [FoundationModelInfo]? = nil
        let modelsURL = URL(fileURLWithPath: "models.json")
        if let data = try? Data(contentsOf: modelsURL) {
            struct Wrapper: Codable { let modelSummaries: [FoundationModelInfo] }
            let wrapper = try JSONDecoder().decode(Wrapper.self, from: data)
            configuredModels = wrapper.modelSummaries
        }

        return AppConfiguration(reader: reader, configuredModels: configuredModels)
    }
}

// MARK: - Model Mapper

struct ModelMapper: Sendable {
    // Provider prefixes used to detect native Bedrock model IDs for passthrough
    private static let bedrockProviderPrefixes: Set<String> = [
        "anthropic.", "amazon.", "deepseek.", "meta.", "mistral.",
        "cohere.", "ai21.", "google.", "qwen.", "stability.", "twelvelabs.",
        "nvidia.", "moonshotai.", "moonshot.", "minimax.", "zai.", "openai.",
    ]

    // Fallback model prefixes for image input support, used when no models.json is configured.
    // Nova Micro, Llama 3.1/3.3, Mistral Large, DeepSeek R1, Cohere, AI21 are excluded.
    private static let imageCapablePrefixes: [String] = [
        "us.anthropic.claude-sonnet-4", "us.anthropic.claude-haiku-4", "us.anthropic.claude-opus-4",
        "anthropic.claude-sonnet-4", "anthropic.claude-haiku-4", "anthropic.claude-opus-4",
        "us.anthropic.claude-3", "anthropic.claude-3",
        "us.amazon.nova-pro", "us.amazon.nova-lite", "amazon.nova-pro", "amazon.nova-lite",
        "us.meta.llama3-2-90b", "us.meta.llama3-2-11b", "meta.llama3-2-90b", "meta.llama3-2-11b",
        "us.mistral.pixtral-large", "mistral.pixtral-large",
    ]

    /// Returns true if the model supports image input.
    /// When models.json is configured, uses `inputModalities` from `FoundationModelInfo`.
    /// Falls back to a hardcoded prefix list when the model is not in configuredModels.
    func supportsImageInput(bedrockID: String) -> Bool {
        if let configured = configuredModels,
           let match = configured.first(where: { bedrockID == $0.modelId || bedrockID.hasSuffix(".\($0.modelId)") }) {
            return match.inputModalities.contains("IMAGE")
        }
        return Self.imageCapablePrefixes.contains { bedrockID.hasPrefix($0) }
    }

    let defaultModel: String
    let configuredModels: [FoundationModelInfo]?
    let crossRegionPrefix: String

    init(defaultModel: String, configuredModels: [FoundationModelInfo]? = nil, crossRegionPrefix: String = "global") {
        self.defaultModel = defaultModel
        self.configuredModels = configuredModels
        self.crossRegionPrefix = crossRegionPrefix
    }

    func bedrockModelID(for model: String) -> String {
        // 1. Native Bedrock ID passthrough — cross-region inference profile prefixes
        //    (us./eu./ap./global.) or direct provider prefixes (anthropic., amazon., etc.).
        //    Using hasPrefix prevents substring-match false positives such as
        //    "hack.me.anthropic.test" incorrectly matching "anthropic.".
        let crossRegionPrefixes = ["us.", "eu.", "ap.", "global."]
        if crossRegionPrefixes.contains(where: { model.hasPrefix($0) }) { return model }
        if Self.bedrockProviderPrefixes.contains(where: { model.hasPrefix($0) }) { return model }
        // 2. Name from models.json (what Xcode sends back after GET /v1/models).
        //    Prepend the configured cross-region prefix only when AWS reports
        //    INFERENCE_PROFILE support and the modelId has no prefix yet.
        if let configured = configuredModels,
           let match = configured.first(where: { $0.modelName == model }) {
            if crossRegionPrefixes.contains(where: { match.modelId.hasPrefix($0) }) {
                return match.modelId
            }
            if match.supportsInferenceProfile {
                return "\(crossRegionPrefix).\(match.modelId)"
            }
            return match.modelId
        }
        return defaultModel
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

    var optionalBedrockService: (any FoundationModelListable)? {
        storage[BedrockServiceKey.self]
    }
}
