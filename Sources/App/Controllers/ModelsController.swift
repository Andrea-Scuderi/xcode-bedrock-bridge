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
        let service = overrideListable ?? req.application.optionalBedrockService

        if let service {
            do {
                let ids = try await service.listFoundationModels()
                if !ids.isEmpty {
                    let models = ids.map { id in
                        ModelObject(id: id, object: "model", created: now, ownedBy: Self.ownedBy(for: id))
                    }
                    return ModelListResponse(object: "list", data: models)
                }
            } catch {
                req.logger.warning("listFoundationModels failed, falling back to static list: \(error)")
            }
        }

        return staticModelList(created: now)
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

    // MARK: - Static fallback

    private func staticModelList(created: Int) -> ModelListResponse {
        // Model IDs sourced from AWS documentation (February 2026):
        // https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html
        // https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
        let ids: [String] = [
            // Claude 4.x
            "us.anthropic.claude-sonnet-4-6",
            "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
            "us.anthropic.claude-sonnet-4-20250514-v1:0",
            "us.anthropic.claude-haiku-4-5-20251001-v1:0",
            "us.anthropic.claude-opus-4-6-v1",
            "us.anthropic.claude-opus-4-5-20251101-v1:0",
            "us.anthropic.claude-opus-4-1-20250805-v1:0",
            // Claude 3.x
            "us.anthropic.claude-3-7-sonnet-20250219-v1:0",
            "us.anthropic.claude-3-5-sonnet-20241022-v2:0",
            "us.anthropic.claude-3-5-sonnet-20240620-v1:0",
            "us.anthropic.claude-3-5-haiku-20241022-v1:0",
            "us.anthropic.claude-3-opus-20240229-v1:0",
            "us.anthropic.claude-3-sonnet-20240229-v1:0",
            "us.anthropic.claude-3-haiku-20240307-v1:0",
            // Amazon Nova
            "us.amazon.nova-pro-v1:0",
            "us.amazon.nova-lite-v1:0",
            "us.amazon.nova-micro-v1:0",
        ]
        let models = ids.map { id in
            ModelObject(id: id, object: "model", created: created, ownedBy: Self.ownedBy(for: id))
        }
        return ModelListResponse(object: "list", data: models)
    }
}
