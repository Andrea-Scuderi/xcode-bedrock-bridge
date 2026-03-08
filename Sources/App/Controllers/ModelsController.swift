import Vapor

struct ModelsController: RouteCollection {
    private let overrideListable: (any FoundationModelListable)?

    init(foundationModelListable: (any FoundationModelListable)? = nil) {
        self.overrideListable = foundationModelListable
    }

    func boot(routes: RoutesBuilder) throws {
        routes.get("v1", "models", use: listModels)
    }

    @Sendable
    func listModels(req: Request) async throws -> ModelListResponse {
        let now = Int(Date().timeIntervalSince1970)
        // Configured models take full priority — skip live AWS call
        if let configured = req.application.appConfiguration.configuredModels {
            return modelList(from: configured, created: now)
        }
        let service = overrideListable ?? req.application.optionalBedrockService
        guard let service else { return fallbackModelList(created: now) }
        do {
            let foundationModels = try await service.listFoundationModels()
            let result = modelList(from: foundationModels, created: now)
            guard !result.data.isEmpty else { return fallbackModelList(created: now) }
            return result
        } catch {
            req.logger.warning("listFoundationModels failed, falling back: \(error)")
            return fallbackModelList(created: now)
        }
    }

    // MARK: - Model list builder

    private func modelList(from summaries: [FoundationModelInfo], created: Int) -> ModelListResponse {
        let models: [ModelObject] = summaries.compactMap { model in
            guard model.isActive else { return nil }
            let displayID = model.modelName ?? model.modelId
            let ownedBy = (model.providerName ?? Self.ownedBy(for: model.modelId)).lowercased()
            return ModelObject(id: displayID, object: "model", created: created, ownedBy: ownedBy)
        }.sorted { $0.id < $1.id }
        return ModelListResponse(object: "list", data: models)
    }

    // MARK: - ownedBy derivation

    /// Derives the provider name from a Bedrock model ID.
    /// Handles both plain IDs (`anthropic.claude-…`, `amazon.nova-…`) and
    /// cross-region inference profile IDs (`us.anthropic.…`, `eu.amazon.…`).
    static func ownedBy(for modelId: String) -> String {
        let parts = modelId.split(separator: ".", maxSplits: 2)
        let first = parts.first.map(String.init) ?? ""
        let regionPrefixes: Set<String> = ["us", "eu", "ap"]
        if regionPrefixes.contains(first), parts.count >= 2 {
            return String(parts[1])
        }
        return first
    }

    // MARK: - Fallback model list

    private func fallbackModelList(created: Int) -> ModelListResponse {
        ModelListResponse(object: "list", data: [])
    }
}
