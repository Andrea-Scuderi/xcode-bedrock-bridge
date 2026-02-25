import Vapor

public func configure(_ app: Application) async throws {
    let config = AppConfiguration()
    app.appConfiguration = config

    // Configure HTTP server port
    app.http.server.configuration.port = config.port

    // Xcode sends large payloads (file contents, tool definitions, conversation history).
    // Raise the body limit to 32 MB to avoid "Payload Too Large" rejections.
    app.routes.defaultMaxBodySize = "32mb"

    // Initialise the Bedrock service (actor)
    let bedrock = BedrockService(region: config.awsRegion, profile: config.awsProfile, bedrockAPIKey: config.bedrockAPIKey)
    app.bedrockService = bedrock

    app.logger.info("Starting xcode-bedrock-bridge")
    app.logger.info("AWS Region: \(config.awsRegion)")
    if config.bedrockAPIKey != nil {
        app.logger.info("Bedrock auth: API key (Bearer token)")
    } else if let profile = config.awsProfile {
        app.logger.info("Bedrock auth: AWS profile '\(profile)'")
    } else {
        app.logger.info("Bedrock auth: default AWS credential chain")
    }
    app.logger.info("Default Bedrock model: \(config.defaultBedrockModel)")
    app.logger.info("Port: \(config.port)")
    if let key = config.proxyAPIKey {
        app.logger.info("API key authentication: enabled")
        if key.count < 16 {
            app.logger.warning("PROXY_API_KEY is shorter than 16 characters — use a longer, random key in production")
        }
    } else {
        app.logger.warning("API key authentication: DISABLED (set PROXY_API_KEY to enable)")
    }

    try routes(app)
}
