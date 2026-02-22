import Vapor

public func routes(_ app: Application) throws {
    let config = app.appConfiguration
    let bedrockService = app.bedrockService
    let modelMapper = ModelMapper(defaultModel: config.defaultBedrockModel)
    let requestTranslator = RequestTranslator()
    let responseTranslator = ResponseTranslator()
    let anthropicRequestTranslator = AnthropicRequestTranslator()
    let anthropicResponseTranslator = AnthropicResponseTranslator()

    // Build the protected route group if an API key is configured.
    // The Anthropic /v1/messages path (used by the Xcode Coding Agent via
    // ANTHROPIC_BASE_URL) is kept on a separate unprotected group because
    // the agent sets its own auth via ANTHROPIC_AUTH_TOKEN, not our proxy key.
    let protected: RoutesBuilder
    if let apiKey = config.proxyAPIKey {
        protected = app.grouped(APIKeyMiddleware(requiredKey: apiKey))
    } else {
        protected = app
    }

    try protected.register(collection: ModelsController())
    try protected.register(collection: ChatController(
        bedrockService: bedrockService,
        modelMapper: modelMapper,
        requestTranslator: requestTranslator,
        responseTranslator: responseTranslator
    ))
    // Anthropic Messages API — used by the Xcode 26.3 Claude Coding Agent.
    // Registered on the base app (not the APIKeyMiddleware group) so the agent's
    // own ANTHROPIC_AUTH_TOKEN is not rejected by our proxy key check.
    try app.register(collection: MessagesController(
        bedrockService: bedrockService,
        modelMapper: modelMapper,
        requestTranslator: anthropicRequestTranslator,
        responseTranslator: anthropicResponseTranslator
    ))
}
