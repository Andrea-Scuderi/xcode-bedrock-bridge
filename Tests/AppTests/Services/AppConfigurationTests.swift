import Testing
import Vapor
@testable import App

@Suite("AppConfiguration Defaults")
struct AppConfigurationDefaultsTests {

    @Test("default region is us-east-1 when AWS_REGION is not set")
    func defaultRegionIsUsEast1() {
        guard ProcessInfo.processInfo.environment["AWS_REGION"] == nil else { return }
        let config = AppConfiguration()
        #expect(config.awsRegion == "us-east-1")
    }

    @Test("default port is 8080 when PORT is not set")
    func defaultPortIs8080() {
        guard ProcessInfo.processInfo.environment["PORT"] == nil else { return }
        let config = AppConfiguration()
        #expect(config.port == 8080)
    }

    @Test("default model is claude-sonnet-4-5 when DEFAULT_BEDROCK_MODEL is not set")
    func defaultModelIsCorrect() {
        guard ProcessInfo.processInfo.environment["DEFAULT_BEDROCK_MODEL"] == nil else { return }
        let config = AppConfiguration()
        #expect(config.defaultBedrockModel == "us.anthropic.claude-sonnet-4-5-20250929-v1:0")
    }

    @Test("default AWS profile is nil when PROFILE is not set")
    func defaultProfileIsNil() {
        guard ProcessInfo.processInfo.environment["PROFILE"] == nil else { return }
        let config = AppConfiguration()
        #expect(config.awsProfile == nil)
    }

    @Test("default proxy API key is nil when PROXY_API_KEY is not set")
    func defaultProxyAPIKeyIsNil() {
        guard ProcessInfo.processInfo.environment["PROXY_API_KEY"] == nil else { return }
        let config = AppConfiguration()
        #expect(config.proxyAPIKey == nil)
    }

    @Test("default Bedrock API key is nil when BEDROCK_API_KEY is not set")
    func defaultBedrockAPIKeyIsNil() {
        guard ProcessInfo.processInfo.environment["BEDROCK_API_KEY"] == nil else { return }
        let config = AppConfiguration()
        #expect(config.bedrockAPIKey == nil)
    }
}
