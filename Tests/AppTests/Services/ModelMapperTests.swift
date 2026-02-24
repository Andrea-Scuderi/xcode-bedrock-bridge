import Testing
@testable import App

@Suite("ModelMapper")
struct ModelMapperTests {

    let mapper = ModelMapper(defaultModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0")

    @Test("gpt-4 maps to Sonnet 4.5")
    func gpt4MapsToSonnet() {
        #expect(mapper.bedrockModelID(for: "gpt-4") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("gpt-3.5-turbo maps to Haiku 4.5")
    func gpt35TurboMapsToHaiku() {
        #expect(mapper.bedrockModelID(for: "gpt-3.5-turbo") == "us.anthropic.claude-haiku-4-5-20251001-v1:0")
    }

    @Test("native us.anthropic Bedrock model ID passes through")
    func passthroughNativeBedrockID() {
        let nativeID = "us.anthropic.claude-3-opus-20240229-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("unknown model falls back to default")
    func unknownModelFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "some-unknown-model") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("claude-3-5-sonnet alias resolves to v2 model")
    func claudeSonnetAlias() {
        #expect(mapper.bedrockModelID(for: "claude-3-5-sonnet") == "us.anthropic.claude-3-5-sonnet-20241022-v2:0")
    }

    @Test("gpt-4o maps to Sonnet 4.5")
    func gpt4oMapsToSonnet() {
        #expect(mapper.bedrockModelID(for: "gpt-4o") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("gpt-4-turbo maps to Sonnet 4.5")
    func gpt4TurboMapsToSonnet() {
        #expect(mapper.bedrockModelID(for: "gpt-4-turbo") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("claude-opus-4-6 alias resolves")
    func claudeOpus4Alias() {
        #expect(mapper.bedrockModelID(for: "claude-opus-4-6") == "us.anthropic.claude-opus-4-6-v1")
    }

    @Test("amazon. prefix model passes through unchanged")
    func nativeBedrockWithAmazonPrefix() {
        let nativeID = "amazon.titan-text-express-v1"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }

    @Test("empty string falls back to default")
    func emptyStringFallsToDefault() {
        #expect(mapper.bedrockModelID(for: "") == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("nova-pro alias resolves to Amazon Nova Pro")
    func novaProAliasResolvesToAmazonNovaPro() {
        #expect(mapper.bedrockModelID(for: "nova-pro") == "us.amazon.nova-pro-v1:0")
    }

    @Test("nova-lite alias resolves to Amazon Nova Lite")
    func novaLiteAliasResolvesToAmazonNovaLite() {
        #expect(mapper.bedrockModelID(for: "nova-lite") == "us.amazon.nova-lite-v1:0")
    }

    @Test("nova-micro alias resolves to Amazon Nova Micro")
    func novaMicroAliasResolvesToAmazonNovaMicro() {
        #expect(mapper.bedrockModelID(for: "nova-micro") == "us.amazon.nova-micro-v1:0")
    }

    @Test("us.amazon. cross-region model ID passes through unchanged")
    func passthroughUsAmazonCrossRegionID() {
        let nativeID = "us.amazon.nova-pro-v1:0"
        #expect(mapper.bedrockModelID(for: nativeID) == nativeID)
    }
}
