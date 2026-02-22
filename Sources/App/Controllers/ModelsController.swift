import Vapor

struct ModelsController: RouteCollection {
    func boot(routes: RoutesBuilder) throws {
        routes.get("v1", "models", use: listModels)
    }

    @Sendable
    func listModels(req: Request) async throws -> ModelListResponse {
        let now = Int(Date().timeIntervalSince1970)

        // Model IDs sourced from AWS documentation (February 2026):
        // https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html
        // https://docs.aws.amazon.com/bedrock/latest/userguide/models-supported.html
        // All use cross-region inference profile IDs (us. prefix) for on-demand throughput.
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
        ]

        let models = ids.map { id in
            ModelObject(id: id, object: "model", created: now, ownedBy: "anthropic")
        }

        return ModelListResponse(object: "list", data: models)
    }
}
