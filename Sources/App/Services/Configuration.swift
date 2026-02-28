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
    }

    /// Reads all values from a pre-built ConfigReader.
    private init(reader: ConfigReader) {
        awsRegion = reader.string(forKey: "aws.region") ?? "us-east-1"
        awsProfile = reader.string(forKey: "profile")
        bedrockAPIKey = reader.string(forKey: "bedrock.api.key")
        defaultBedrockModel = reader.string(forKey: "default.bedrock.model")
            ?? "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
        proxyAPIKey = reader.string(forKey: "proxy.api.key")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        port = reader.int(forKey: "port") ?? 8080
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
        return AppConfiguration(reader: reader)
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

        // Amazon Nova
        "nova-pro":            "us.amazon.nova-pro-v1:0",
        "nova-lite":           "us.amazon.nova-lite-v1:0",
        "nova-micro":          "us.amazon.nova-micro-v1:0",

        // DeepSeek
        "deepseek-r1":         "us.deepseek.r1-v1:0",

        // Meta Llama 3.x / 4.x
        "llama-3-3-70b":       "us.meta.llama3-3-70b-instruct-v1:0",
        "llama-3-1-405b":      "us.meta.llama3-1-405b-instruct-v1:0",
        "llama-3-1-70b":       "us.meta.llama3-1-70b-instruct-v1:0",
        "llama-3-1-8b":        "us.meta.llama3-1-8b-instruct-v1:0",
        "llama-3-2-90b":       "us.meta.llama3-2-90b-instruct-v1:0",
        "llama-3-2-11b":       "us.meta.llama3-2-11b-instruct-v1:0",
        "llama-4-maverick":    "us.meta.llama4-maverick-17b-instruct-v1:0",
        "llama-4-scout":       "us.meta.llama4-scout-17b-instruct-v1:0",

        // Mistral
        "mistral-large":       "mistral.mistral-large-2407-v1:0",
        "mistral-small":       "mistral.mistral-small-2402-v1:0",
        "mixtral-8x7b":        "mistral.mixtral-8x7b-instruct-v0:1",
        "pixtral-large":       "us.mistral.pixtral-large-2502-v1:0",

        // Cohere
        "command-r-plus":      "cohere.command-r-plus-v1:0",
        "command-r":           "cohere.command-r-v1:0",

        // AI21 Jamba
        "jamba-large":         "ai21.jamba-1-5-large-v1:0",
        "jamba-mini":          "ai21.jamba-1-5-mini-v1:0",
    ]

    // Provider prefixes used to detect native Bedrock model IDs for passthrough
    private static let bedrockProviderPrefixes: Set<String> = [
        "anthropic.", "amazon.", "deepseek.", "meta.", "mistral.",
        "cohere.", "ai21.", "google.", "qwen.", "stability.", "twelvelabs.",
        "nvidia.", "moonshotai.", "moonshot.", "minimax.", "zai.", "openai.",
    ]

    /// Maps human-readable Bedrock modelName values to Bedrock model IDs (cross-region profiles
    /// where available, otherwise direct model IDs). Used to resolve model names that Xcode sends
    /// after receiving them from GET /v1/models. Names confirmed against listFoundationModels output
    /// unless marked as cross-region inference profile (not returned by listFoundationModels).
    static let modelNameToBedrockID: [String: String] = [
        // Claude 4.x — cross-region inference profiles (not returned by listFoundationModels)
        "Claude Sonnet 4.6":                    "us.anthropic.claude-sonnet-4-6",
        "Claude Sonnet 4.5":                    "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
        "Claude Sonnet 4":                      "us.anthropic.claude-sonnet-4-20250514-v1:0",
        "Claude Haiku 4.5":                     "us.anthropic.claude-haiku-4-5-20251001-v1:0",
        "Claude Opus 4.6":                      "us.anthropic.claude-opus-4-6-v1",
        "Claude Opus 4.5":                      "us.anthropic.claude-opus-4-5-20251101-v1:0",
        "Claude Opus 4.1":                      "us.anthropic.claude-opus-4-1-20250805-v1:0",
        // Claude 3.7 — cross-region inference profile
        "Claude 3.7 Sonnet":                    "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
        // Claude 3.5 — v2/Haiku are cross-region; classic v1 is LEGACY in listFoundationModels
        "Claude 3.5 Sonnet v2":                 "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
        "Claude 3.5 Sonnet":                    "us.anthropic.claude-3-5-sonnet-20240620-v1:0",
        "Claude 3.5 Haiku":                     "us.anthropic.claude-3-5-haiku-20241022-v1:0",
        // Claude 3 — confirmed from listFoundationModels (Haiku: ACTIVE; Sonnet/Opus: LEGACY)
        "Claude 3 Opus":                        "us.anthropic.claude-3-opus-20240229-v1:0",
        "Claude 3 Sonnet":                      "us.anthropic.claude-3-sonnet-20240229-v1:0",
        "Claude 3 Haiku":                       "us.anthropic.claude-3-haiku-20240307-v1:0",
        // Amazon Nova — names confirmed from listFoundationModels; values use cross-region profiles
        "Nova Pro":                             "us.amazon.nova-pro-v1:0",
        "Nova Lite":                            "us.amazon.nova-lite-v1:0",
        "Nova Micro":                           "us.amazon.nova-micro-v1:0",
        "Nova Sonic":                           "amazon.nova-sonic-v1:0",
        "Nova 2 Sonic":                         "amazon.nova-2-sonic-v1:0",
        "Titan Text Large":                     "amazon.titan-tg1-large",
        // DeepSeek — R1 is cross-region; V3.2 confirmed from listFoundationModels
        "DeepSeek-R1":                          "us.deepseek.r1-v1:0",
        "DeepSeek V3.2":                        "deepseek.v3.2",
        // Meta Llama — cross-region inference profiles
        "Llama 3.3 70B Instruct":               "us.meta.llama3-3-70b-instruct-v1:0",
        "Llama 3.1 405B Instruct":              "us.meta.llama3-1-405b-instruct-v1:0",
        "Llama 3.1 70B Instruct":               "us.meta.llama3-1-70b-instruct-v1:0",
        "Llama 3.1 8B Instruct":                "us.meta.llama3-1-8b-instruct-v1:0",
        "Llama 3.2 90B Instruct":               "us.meta.llama3-2-90b-instruct-v1:0",
        "Llama 3.2 11B Instruct":               "us.meta.llama3-2-11b-instruct-v1:0",
        "Llama 4 Maverick 17B Instruct":        "us.meta.llama4-maverick-17b-instruct-v1:0",
        "Llama 4 Scout 17B Instruct":           "us.meta.llama4-scout-17b-instruct-v1:0",
        // Meta Llama — base models confirmed from listFoundationModels
        "Llama 3 8B Instruct":                  "meta.llama3-8b-instruct-v1:0",
        "Llama 3 70B Instruct":                 "meta.llama3-70b-instruct-v1:0",
        // Mistral — names confirmed from listFoundationModels
        "Mistral Large (24.02)":                "mistral.mistral-large-2402-v1:0",
        "Mistral Large 3":                      "mistral.mistral-large-3-675b-instruct",
        "Mistral Small (24.02)":                "mistral.mistral-small-2402-v1:0",
        "Mistral 7B Instruct":                  "mistral.mistral-7b-instruct-v0:2",
        "Mixtral 8x7B Instruct":                "mistral.mixtral-8x7b-instruct-v0:1",
        "Magistral Small 2509":                 "mistral.magistral-small-2509",
        "Devstral 2 123B":                      "mistral.devstral-2-123b",
        "Ministral 3B":                         "mistral.ministral-3-3b-instruct",
        "Ministral 3 8B":                       "mistral.ministral-3-8b-instruct",
        "Ministral 14B 3.0":                    "mistral.ministral-3-14b-instruct",
        "Voxtral Mini 3B 2507":                 "mistral.voxtral-mini-3b-2507",
        "Voxtral Small 24B 2507":               "mistral.voxtral-small-24b-2507",
        // Mistral — cross-region inference profile (not in listFoundationModels)
        "Pixtral Large (2502)":                 "us.mistral.pixtral-large-2502-v1:0",
        // Cohere — confirmed from listFoundationModels
        "Command R+":                           "cohere.command-r-plus-v1:0",
        "Command R":                            "cohere.command-r-v1:0",
        "Rerank 3.5":                           "cohere.rerank-v3-5:0",
        // AI21 Jamba — confirmed from listFoundationModels
        "Jamba 1.5 Large":                      "ai21.jamba-1-5-large-v1:0",
        "Jamba 1.5 Mini":                       "ai21.jamba-1-5-mini-v1:0",
        // Google Gemma — confirmed from listFoundationModels
        "Gemma 3 4B IT":                        "google.gemma-3-4b-it",
        "Gemma 3 12B IT":                       "google.gemma-3-12b-it",
        "Gemma 3 27B PT":                       "google.gemma-3-27b-it",
        // Qwen — confirmed from listFoundationModels
        "Qwen3 32B (dense)":                    "qwen.qwen3-32b-v1:0",
        "Qwen3 Next 80B A3B":                   "qwen.qwen3-next-80b-a3b",
        "Qwen3 Coder Next":                     "qwen.qwen3-coder-next",
        "Qwen3-Coder-30B-A3B-Instruct":         "qwen.qwen3-coder-30b-a3b-v1:0",
        "Qwen3 VL 235B A22B":                   "qwen.qwen3-vl-235b-a22b",
        // NVIDIA Nemotron — confirmed from listFoundationModels
        "NVIDIA Nemotron Nano 12B v2 VL BF16":  "nvidia.nemotron-nano-12b-v2",
        "NVIDIA Nemotron Nano 9B v2":           "nvidia.nemotron-nano-9b-v2",
        "Nemotron Nano 3 30B":                  "nvidia.nemotron-nano-3-30b",
        // Moonshot AI / Kimi — confirmed from listFoundationModels
        "Kimi K2.5":                            "moonshotai.kimi-k2.5",
        "Kimi K2 Thinking":                     "moonshot.kimi-k2-thinking",
        // MiniMax — confirmed from listFoundationModels
        "MiniMax M2":                           "minimax.minimax-m2",
        "MiniMax M2.1":                         "minimax.minimax-m2.1",
        // Z.AI — confirmed from listFoundationModels
        "GLM 4.7":                              "zai.glm-4.7",
        "GLM 4.7 Flash":                        "zai.glm-4.7-flash",
        // OpenAI on Bedrock — confirmed from listFoundationModels
        "gpt-oss-120b":                         "openai.gpt-oss-120b-1:0",
        "gpt-oss-20b":                          "openai.gpt-oss-20b-1:0",
        "GPT OSS Safeguard 120B":               "openai.gpt-oss-safeguard-120b",
        "GPT OSS Safeguard 20B":                "openai.gpt-oss-safeguard-20b",
        // TwelveLabs — confirmed from listFoundationModels
        "Pegasus v1.2":                         "twelvelabs.pegasus-1-2-v1:0",
    ]

    // Model prefixes that support image input via the Bedrock Converse API.
    // Nova Micro, Llama 3.1/3.3, Mistral Large, DeepSeek R1, Cohere, AI21 are excluded.
    private static let imageCapablePrefixes: [String] = [
        "us.anthropic.claude-sonnet-4", "us.anthropic.claude-haiku-4", "us.anthropic.claude-opus-4",
        "anthropic.claude-sonnet-4", "anthropic.claude-haiku-4", "anthropic.claude-opus-4",
        "us.anthropic.claude-3", "anthropic.claude-3",
        "us.amazon.nova-pro", "us.amazon.nova-lite", "amazon.nova-pro", "amazon.nova-lite",
        "us.meta.llama3-2-90b", "us.meta.llama3-2-11b", "meta.llama3-2-90b", "meta.llama3-2-11b",
        "us.mistral.pixtral-large", "mistral.pixtral-large",
    ]

    static func supportsImageInput(bedrockID: String) -> Bool {
        imageCapablePrefixes.contains { bedrockID.hasPrefix($0) }
    }

    let defaultModel: String

    func bedrockModelID(for model: String) -> String {
        // 1. Native Bedrock ID passthrough — cross-region inference profile prefixes
        //    (us./eu./ap.) or direct provider prefixes (anthropic., amazon., etc.).
        //    Using hasPrefix prevents substring-match false positives such as
        //    "hack.me.anthropic.test" incorrectly matching "anthropic.".
        let crossRegionPrefixes = ["us.", "eu.", "ap."]
        if crossRegionPrefixes.contains(where: { model.hasPrefix($0) }) { return model }
        if Self.bedrockProviderPrefixes.contains(where: { model.hasPrefix($0) }) { return model }
        // 2. Short alias (gpt-4, claude-3-5-sonnet, nova-pro, etc.)
        if let mapped = Self.mapping[model] { return mapped }
        // 3. Human-readable name sent back by Xcode after GET /v1/models
        if let mapped = Self.modelNameToBedrockID[model] { return mapped }
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
