import Testing
import VaporTesting
@testable import App

// MARK: - Mock

private struct MockFoundationModelListable: FoundationModelListable {
    enum Behavior {
        case success([String])
        case empty
        case failure(Error)
    }

    let behavior: Behavior

    func listFoundationModels() async throws -> [String] {
        switch behavior {
        case .success(let ids): return ids
        case .empty: return []
        case .failure(let error): throw error
        }
    }
}

private struct MockListError: Error {}

// MARK: - ownedBy derivation

@Suite("ModelsController ownedBy derivation")
struct ModelsControllerOwnedByTests {

    @Test("anthropic. prefix returns anthropic")
    func anthropicPrefixReturnsAnthropic() {
        #expect(ModelsController.ownedBy(for: "anthropic.claude-3-haiku-20240307-v1:0") == "anthropic")
    }

    @Test("amazon. prefix returns amazon")
    func amazonPrefixReturnsAmazon() {
        #expect(ModelsController.ownedBy(for: "amazon.nova-pro-v1:0") == "amazon")
    }

    @Test("us.anthropic. cross-region prefix returns anthropic")
    func usAnthropicPrefixReturnsAnthropic() {
        #expect(ModelsController.ownedBy(for: "us.anthropic.claude-sonnet-4-6") == "anthropic")
    }

    @Test("us.amazon. cross-region prefix returns amazon")
    func usAmazonPrefixReturnsAmazon() {
        #expect(ModelsController.ownedBy(for: "us.amazon.nova-pro-v1:0") == "amazon")
    }

    @Test("eu.anthropic. cross-region prefix returns anthropic")
    func euAnthropicPrefixReturnsAnthropic() {
        #expect(ModelsController.ownedBy(for: "eu.anthropic.claude-3-haiku-20240307-v1:0") == "anthropic")
    }

    @Test("ap.amazon. cross-region prefix returns amazon")
    func apAmazonPrefixReturnsAmazon() {
        #expect(ModelsController.ownedBy(for: "ap.amazon.nova-lite-v1:0") == "amazon")
    }
}

// MARK: - Static fallback suite (no BedrockService injected)

@Suite("ModelsController")
struct ModelsControllerTests {

    @Test("returns 200 without auth")
    func returnsOKWithoutAuth() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            #expect(res.status == .ok)
        }
    }

    @Test("response body is list object with data")
    func responseBodyIsListObject() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            let body = try? res.content.decode(ModelListResponse.self)
            #expect(body?.object == "list")
            #expect((body?.data.count ?? 0) > 0)
        }
    }

    @Test("response contains expected Anthropic model IDs")
    func responseContainsExpectedAnthropicModelIDs() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                let ids = body.data.map(\.id)
                #expect(ids.contains("us.anthropic.claude-3-5-sonnet-20241022-v2:0"))
                #expect(ids.contains("us.anthropic.claude-3-haiku-20240307-v1:0"))
            }
        }
    }

    @Test("response contains expected Amazon Nova model IDs")
    func responseContainsExpectedAmazonModelIDs() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                let ids = body.data.map(\.id)
                #expect(ids.contains("us.amazon.nova-pro-v1:0"))
                #expect(ids.contains("us.amazon.nova-lite-v1:0"))
                #expect(ids.contains("us.amazon.nova-micro-v1:0"))
            }
        }
    }

    @Test("Anthropic models have owned_by anthropic")
    func anthropicModelsHaveOwnedByAnthropic() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                let anthropicModels = body.data.filter { $0.id.contains("anthropic") }
                #expect(!anthropicModels.isEmpty)
                #expect(anthropicModels.allSatisfy { $0.ownedBy == "anthropic" })
            }
        }
    }

    @Test("Amazon models have owned_by amazon")
    func amazonModelsHaveOwnedByAmazon() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                let amazonModels = body.data.filter { $0.id.contains("amazon") }
                #expect(!amazonModels.isEmpty)
                #expect(amazonModels.allSatisfy { $0.ownedBy == "amazon" })
            }
        }
    }

    @Test("all models have object type 'model'")
    func allModelsHaveModelObjectType() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                #expect(body.data.allSatisfy { $0.object == "model" })
            }
        }
    }
}

// MARK: - Dynamic list suite (mock BedrockService injected)

@Suite("ModelsController dynamic list")
struct ModelsControllerDynamicListTests {

    @Test("returns dynamic model IDs from service")
    func returnsDynamicListFromService() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .success([
            "anthropic.claude-3-haiku-20240307-v1:0",
            "amazon.nova-pro-v1:0",
        ]))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            let body = try? res.content.decode(ModelListResponse.self)
            let ids = body?.data.map(\.id) ?? []
            #expect(ids == ["anthropic.claude-3-haiku-20240307-v1:0", "amazon.nova-pro-v1:0"])
        }
    }

    @Test("dynamic Anthropic models have owned_by anthropic")
    func dynamicAnthropicModelsHaveCorrectOwnedBy() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .success(["anthropic.claude-3-haiku-20240307-v1:0"]))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                #expect(body.data.allSatisfy { $0.ownedBy == "anthropic" })
            }
        }
    }

    @Test("dynamic Amazon models have owned_by amazon")
    func dynamicAmazonModelsHaveCorrectOwnedBy() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .success([
            "amazon.nova-pro-v1:0",
            "us.amazon.nova-lite-v1:0",
        ]))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                #expect(body.data.allSatisfy { $0.ownedBy == "amazon" })
            }
        }
    }

    @Test("mixed provider list has correct ownedBy per model")
    func mixedProviderListHasCorrectOwnedBy() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .success([
            "anthropic.claude-3-haiku-20240307-v1:0",
            "amazon.nova-pro-v1:0",
        ]))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                let byId = Dictionary(uniqueKeysWithValues: body.data.map { ($0.id, $0.ownedBy) })
                #expect(byId["anthropic.claude-3-haiku-20240307-v1:0"] == "anthropic")
                #expect(byId["amazon.nova-pro-v1:0"] == "amazon")
            }
        }
    }

    @Test("dynamic models all have object type 'model'")
    func dynamicModelsHaveCorrectObjectType() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .success([
            "anthropic.claude-3-haiku-20240307-v1:0",
            "amazon.nova-pro-v1:0",
        ]))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                #expect(body.data.allSatisfy { $0.object == "model" })
            }
        }
    }

    @Test("falls back to static list when service throws")
    func fallsBackToStaticListWhenServiceThrows() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .failure(MockListError()))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            let body = try? res.content.decode(ModelListResponse.self)
            let ids = body?.data.map(\.id) ?? []
            #expect(ids.contains("us.anthropic.claude-3-5-sonnet-20241022-v2:0"))
            #expect(ids.contains("us.amazon.nova-pro-v1:0"))
        }
    }

    @Test("falls back to static list when service returns empty array")
    func fallsBackToStaticListWhenServiceReturnsEmpty() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .empty)
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            let body = try? res.content.decode(ModelListResponse.self)
            let ids = body?.data.map(\.id) ?? []
            #expect(ids.contains("us.anthropic.claude-3-5-sonnet-20241022-v2:0"))
            #expect(ids.contains("us.amazon.nova-pro-v1:0"))
        }
    }

    @Test("returns 200 when service throws")
    func returns200WhenServiceThrows() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let mock = MockFoundationModelListable(behavior: .failure(MockListError()))
        try app.register(collection: ModelsController(foundationModelListable: mock))

        try await app.test(.GET, "/v1/models") { res async in
            #expect(res.status == .ok)
        }
    }
}
