import Testing
@testable import App

@Suite("ModelMapper")
struct ModelMapperTests {

    let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")

    // MARK: - Tier 1: native Bedrock ID passthrough

    @Test("native us.anthropic Bedrock model ID passes through")
    func passthroughNativeBedrockID() {
        let nativeID = "us.anthropic.claude-3-opus-20240229-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("amazon. prefix model passes through unchanged")
    func nativeBedrockWithAmazonPrefix() {
        let nativeID = "amazon.titan-text-express-v1"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("us.amazon. cross-region model ID passes through unchanged")
    func passthroughUsAmazonCrossRegionID() {
        let nativeID = "us.amazon.nova-pro-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("native us.deepseek model ID passes through unchanged")
    func passthroughNativeDeepseekID() {
        let nativeID = "us.deepseek.r1-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("native us.meta model ID passes through unchanged")
    func passthroughNativeMetaID() {
        let nativeID = "us.meta.llama3-3-70b-instruct-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("native mistral. model ID passes through unchanged")
    func passthroughNativeMistralID() {
        let nativeID = "mistral.mistral-large-2407-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("native cohere. model ID passes through unchanged")
    func passthroughNativeCohereID() {
        let nativeID = "cohere.command-r-plus-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("embedded provider prefix does not trigger passthrough")
    func embeddedProviderPrefixFallsToDefault() {
        // "hack.me.anthropic.test" contains "anthropic." but must NOT pass through —
        // only strings that *start with* a known prefix are native Bedrock IDs.
        #expect(mapper.bedrockModelID(for: "hack.me.anthropic.test") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    // MARK: - Tier 2: configuredModels (models.json)

    @Test("configured model with INFERENCE_PROFILE gets configured prefix")
    func configuredModelWithInferenceProfileGetsConfiguredPrefix() {
        for prefix in ["global", "us", "eu", "ap"] {
            let mapperWithConfig = ModelMapper(
                defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
                configuredModels: [
                    FoundationModelInfo(modelId: "anthropic.claude-sonnet-4-5-20250929-v1:0", modelName: "Claude Sonnet 4.5", isActive: true, inferenceTypesSupported: ["INFERENCE_PROFILE"]),
                    FoundationModelInfo(modelId: "amazon.nova-pro-v1:0", modelName: "Nova Pro", isActive: true, inferenceTypesSupported: ["ON_DEMAND", "INFERENCE_PROFILE"]),
                ],
                crossRegionPrefix: prefix
            )
            #expect(mapperWithConfig.bedrockModelID(for: "Claude Sonnet 4.5") == "\(prefix).anthropic.claude-sonnet-4-5-20250929-v1:0")
            #expect(mapperWithConfig.bedrockModelID(for: "Nova Pro") == "\(prefix).amazon.nova-pro-v1:0")
        }
    }

    @Test("configured model without INFERENCE_PROFILE is not prefixed")
    func configuredModelWithoutInferenceProfileNotPrefixed() {
        let mapperWithConfig = ModelMapper(
            defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            configuredModels: [
                FoundationModelInfo(modelId: "cohere.embed-english-v3", modelName: "Embed English", isActive: true, inferenceTypesSupported: ["ON_DEMAND"]),
            ]
        )
        #expect(mapperWithConfig.bedrockModelID(for: "Embed English") == "cohere.embed-english-v3")
    }

    @Test("configuredModels modelId already cross-region passes through unchanged")
    func configuredModelsAlreadyCrossRegionPassesThrough() {
        let mapperWithConfig = ModelMapper(
            defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            configuredModels: [
                FoundationModelInfo(modelId: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", modelName: "My Model", isActive: true, inferenceTypesSupported: ["INFERENCE_PROFILE"]),
            ]
        )
        #expect(mapperWithConfig.bedrockModelID(for: "My Model") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("global. prefixed model ID passes through via tier-1")
    func globalPrefixPassesThroughTierOne() {
        let nativeID = "global.anthropic.claude-sonnet-4-5-20250929-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("name not in configuredModels returns defaultModel")
    func returnsDefaultWhenNameNotInConfiguredModels() {
        let mapperWithConfig = ModelMapper(
            defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            configuredModels: [
                FoundationModelInfo(modelId: "amazon.nova-pro-v1:0", modelName: "Known Model", isActive: true, inferenceTypesSupported: ["ON_DEMAND"]),
            ]
        )
        #expect(mapperWithConfig.bedrockModelID(for: "Unknown Model") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    // MARK: - Default fallback

    @Test("unknown model falls back to default")
    func unknownModelFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "some-unknown-model") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("empty string falls back to default")
    func emptyStringFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("nil configuredModels falls back to default for any name")
    func nilConfiguredModelsFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "Claude Sonnet 4.5") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    // MARK: - supportsImageInput

    @Test("Claude 3 Haiku supports image input")
    func claude3HaikuSupportsImages() {
        #expect(mapper.supportsImageInput(bedrockID: "us.anthropic.claude-3-haiku-20240307-v1:0"))
    }

    @Test("Claude Sonnet 4.5 supports image input")
    func claudeSonnet45SupportsImages() {
        #expect(mapper.supportsImageInput(bedrockID: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"))
    }

    @Test("Nova Pro supports image input")
    func novaProSupportsImages() {
        #expect(mapper.supportsImageInput(bedrockID: "us.amazon.nova-pro-v1:0"))
    }

    @Test("Nova Lite supports image input")
    func novaLiteSupportsImages() {
        #expect(mapper.supportsImageInput(bedrockID: "us.amazon.nova-lite-v1:0"))
    }

    @Test("Nova Micro does NOT support image input")
    func novaMicroDoesNotSupportImages() {
        #expect(!mapper.supportsImageInput(bedrockID: "us.amazon.nova-micro-v1:0"))
    }

    @Test("Llama 3.2 90B supports image input")
    func llama3290bSupportsImages() {
        #expect(mapper.supportsImageInput(bedrockID: "us.meta.llama3-2-90b-instruct-v1:0"))
    }

    @Test("Llama 3.1 405B does NOT support image input")
    func llama31405bDoesNotSupportImages() {
        #expect(!mapper.supportsImageInput(bedrockID: "us.meta.llama3-1-405b-instruct-v1:0"))
    }

    @Test("Pixtral Large supports image input")
    func pixtralLargeSupportsImages() {
        #expect(mapper.supportsImageInput(bedrockID: "us.mistral.pixtral-large-2502-v1:0"))
    }

    @Test("Mistral Large does NOT support image input")
    func mistralLargeDoesNotSupportImages() {
        #expect(!mapper.supportsImageInput(bedrockID: "mistral.mistral-large-2407-v1:0"))
    }

    @Test("unknown model does NOT support image input")
    func unknownModelDoesNotSupportImages() {
        #expect(!mapper.supportsImageInput(bedrockID: "some-unknown-model"))
    }

    @Test("configuredModels with IMAGE modality reports image support")
    func configuredModelWithImageModalitySupportsImages() {
        let mapperWithConfig = ModelMapper(
            defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            configuredModels: [
                FoundationModelInfo(modelId: "amazon.nova-micro-v1:0", modelName: "Nova Micro", isActive: true,
                                    inputModalities: ["TEXT"], inferenceTypesSupported: ["ON_DEMAND"]),
                FoundationModelInfo(modelId: "amazon.nova-pro-v1:0", modelName: "Nova Pro", isActive: true,
                                    inputModalities: ["TEXT", "IMAGE"], inferenceTypesSupported: ["ON_DEMAND", "INFERENCE_PROFILE"]),
            ]
        )
        // Nova Pro has IMAGE in inputModalities — should return true even for prefixed ID
        #expect(mapperWithConfig.supportsImageInput(bedrockID: "global.amazon.nova-pro-v1:0"))
        // Nova Micro has only TEXT — should return false even though prefix list would normally say nothing
        #expect(!mapperWithConfig.supportsImageInput(bedrockID: "amazon.nova-micro-v1:0"))
    }

    @Test("configuredModels overrides prefix-list heuristic")
    func configuredModelsOverridesPrefixList() {
        // Normally "us.amazon.nova-lite-v1:0" would match the hardcoded prefix list.
        // When configuredModels is present and says TEXT-only, that takes priority.
        let mapperWithConfig = ModelMapper(
            defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            configuredModels: [
                FoundationModelInfo(modelId: "amazon.nova-lite-v1:0", modelName: "Nova Lite", isActive: true,
                                    inputModalities: ["TEXT"], inferenceTypesSupported: ["ON_DEMAND"]),
            ]
        )
        #expect(!mapperWithConfig.supportsImageInput(bedrockID: "us.amazon.nova-lite-v1:0"))
    }
}
