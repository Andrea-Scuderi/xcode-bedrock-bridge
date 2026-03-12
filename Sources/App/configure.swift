import Vapor

public func configure(_ app: Application) async throws {
    let config = try await AppConfiguration.load()
    app.appConfiguration = config

    // Bind host — defaults to 127.0.0.1 (localhost-only) for local dev safety.
    // Set BIND_HOST=0.0.0.0 in Docker or when accepting remote connections.
    app.http.server.configuration.hostname = config.bindHost

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
    app.logger.info("Cross-region prefix: \(config.crossRegionPrefix)")
    if let models = config.configuredModels {
        app.logger.info("Configured models: \(models.count) entries loaded from models.json")
        for model in models.sorted(by: { ($0.modelName ?? $0.modelId) < ($1.modelName ?? $1.modelId) }) {
            let name = model.modelName ?? model.modelId
            let active = model.isActive ? "" : " (inactive)"
            app.logger.info("  - \(name): \(model.modelId)\(active)")
        }
    } else {
        app.logger.info("Configured models: none (models.json not found — using live AWS list)")
    }
    app.logger.info("Port: \(config.port)")
    app.logger.info("Bind host: \(config.bindHost)")
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
