import Testing
import VaporTesting
@testable import App

// MARK: - Mock

private struct MockFoundationModelListable: FoundationModelListable {
    enum Behavior {
        case success([FoundationModelInfo])
        case empty
        case failure(Error)
    }

    let behavior: Behavior

    func listFoundationModels() async throws -> [FoundationModelInfo] {
        switch behavior {
        case .success(let models): return models
        case .empty: return []
        case .failure(let error): throw error
        }
    }
}

private func makeInfo(
    modelId: String,
    modelName: String? = nil,
    providerName: String? = nil,
    isActive: Bool = true
) -> FoundationModelInfo {
    FoundationModelInfo(modelId: modelId, modelName: modelName, providerName: providerName, isActive: isActive)
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

// MARK: - Static fallback suite (no BedrockService injected, no configuredModels)

@Suite("ModelsController")
struct ModelsControllerTests {

    @Test("returns 200 without auth")
    func returnsOKWithoutAuth() async throws {
        try await withApp({ app in
            try app.register(collection: ModelsController())
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                #expect(res.status == .ok)
            }
        }
    }

    @Test("returns empty list when no models.json and no service")
    func returnsEmptyListWhenNoConfigAndNoService() async throws {
        try await withApp({ app in
            try app.register(collection: ModelsController())
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                #expect(body?.object == "list")
                #expect(body?.data.isEmpty == true)
            }
        }
    }

    @Test("all models have object type 'model'")
    func allModelsHaveModelObjectType() async throws {
        try await withApp({ app in
            try app.register(collection: ModelsController())
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                if let body = try? res.content.decode(ModelListResponse.self) {
                    #expect(body.data.allSatisfy { $0.object == "model" })
                }
            }
        }
    }
}

// MARK: - Configured models suite (models.json present)

@Suite("ModelsController configured models")
struct ModelsControllerConfiguredModelsTests {

    @Test("configured models are returned when present")
    func configuredModelsAreReturnedWhenPresent() async throws {
        let configured: [FoundationModelInfo] = [
            makeInfo(modelId: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", modelName: "Claude Sonnet 4.5", providerName: "Anthropic"),
            makeInfo(modelId: "us.amazon.nova-pro-v1:0", modelName: "Nova Pro", providerName: "Amazon"),
        ]
        try await withApp({ app in
            app.appConfiguration = AppConfiguration(
                awsRegion: "us-east-1",
                awsProfile: nil,
                bedrockAPIKey: nil,
                defaultBedrockModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
                proxyAPIKey: nil,
                port: 8080,
                bindHost: "127.0.0.1",
                configuredModels: configured
            )
            try app.register(collection: ModelsController())
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                let ids = body?.data.map(\.id) ?? []
                #expect(ids.contains("Claude Sonnet 4.5"))
                #expect(ids.contains("Nova Pro"))
                #expect(ids.count == 2)
            }
        }
    }

    @Test("configured models skip live AWS list")
    func configuredModelsSkipLiveList() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0", modelName: "Claude 3 Haiku"),
        ]))
        let configured: [FoundationModelInfo] = [
            makeInfo(modelId: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", modelName: "My Model"),
        ]
        try await withApp({ app in
            app.appConfiguration = AppConfiguration(
                awsRegion: "us-east-1",
                awsProfile: nil,
                bedrockAPIKey: nil,
                defaultBedrockModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
                proxyAPIKey: nil,
                port: 8080,
                bindHost: "127.0.0.1",
                configuredModels: configured
            )
            // Even if a listable is injected, configured models take priority
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                let ids = body?.data.map(\.id) ?? []
                #expect(ids.contains("My Model"))
                #expect(!ids.contains("Claude 3 Haiku"))
            }
        }
    }

    @Test("configured models sorted alphabetically")
    func configuredModelsSortedAlphabetically() async throws {
        let configured: [FoundationModelInfo] = [
            makeInfo(modelId: "us.amazon.nova-pro-v1:0", modelName: "Zeta Model"),
            makeInfo(modelId: "us.anthropic.claude-sonnet-4-5-20250929-v1:0", modelName: "Alpha Model"),
            makeInfo(modelId: "us.anthropic.claude-haiku-4-5-20251001-v1:0", modelName: "Mu Model"),
        ]
        try await withApp({ app in
            app.appConfiguration = AppConfiguration(
                awsRegion: "us-east-1",
                awsProfile: nil,
                bedrockAPIKey: nil,
                defaultBedrockModel: "us.anthropic.claude-sonnet-4-5-20250929-v1:0",
                proxyAPIKey: nil,
                port: 8080,
                bindHost: "127.0.0.1",
                configuredModels: configured
            )
            try app.register(collection: ModelsController())
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                let ids = body?.data.map(\.id) ?? []
                #expect(ids == ids.sorted())
            }
        }
    }
}

// MARK: - Dynamic list suite (mock BedrockService injected)

@Suite("ModelsController dynamic list")
struct ModelsControllerDynamicListTests {

    @Test("returns modelName as id when provided")
    func returnsModelNameAsId() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0", modelName: "Claude 3 Haiku"),
            makeInfo(modelId: "amazon.nova-pro-v1:0", modelName: "Amazon Nova Pro"),
        ]))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                let ids = body?.data.map(\.id) ?? []
                #expect(ids.contains("Claude 3 Haiku"))
                #expect(ids.contains("Amazon Nova Pro"))
            }
        }
    }

    @Test("falls back to modelId when modelName is nil")
    func fallsBackToModelIdWhenNameIsNil() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0"),
        ]))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                let ids = body?.data.map(\.id) ?? []
                #expect(ids.contains("anthropic.claude-3-haiku-20240307-v1:0"))
            }
        }
    }

    @Test("uses providerName as ownedBy when provided")
    func usesProviderNameAsOwnedBy() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0", modelName: "Claude 3 Haiku", providerName: "Anthropic"),
        ]))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                if let body = try? res.content.decode(ModelListResponse.self) {
                    #expect(body.data.allSatisfy { $0.ownedBy == "anthropic" })
                }
            }
        }
    }

    @Test("falls back to derived ownedBy when providerName is nil")
    func fallsBackToDerivedOwnedBy() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0", modelName: "Claude 3 Haiku"),
            makeInfo(modelId: "amazon.nova-pro-v1:0", modelName: "Amazon Nova Pro"),
        ]))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                if let body = try? res.content.decode(ModelListResponse.self) {
                    let byId = Dictionary(uniqueKeysWithValues: body.data.map { ($0.id, $0.ownedBy) })
                    #expect(byId["Claude 3 Haiku"] == "anthropic")
                    #expect(byId["Amazon Nova Pro"] == "amazon")
                }
            }
        }
    }

    @Test("inactive models are excluded from response")
    func inactiveModelsAreExcluded() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0", modelName: "Claude 3 Haiku", isActive: true),
            makeInfo(modelId: "anthropic.old-model-v1:0", modelName: "Old Model", isActive: false),
        ]))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                let ids = body?.data.map(\.id) ?? []
                #expect(ids.contains("Claude 3 Haiku"))
                #expect(!ids.contains("Old Model"))
            }
        }
    }

    @Test("dynamic models all have object type 'model'")
    func dynamicModelsHaveCorrectObjectType() async throws {
        let mock = MockFoundationModelListable(behavior: .success([
            makeInfo(modelId: "anthropic.claude-3-haiku-20240307-v1:0", modelName: "Claude 3 Haiku"),
            makeInfo(modelId: "amazon.nova-pro-v1:0", modelName: "Amazon Nova Pro"),
        ]))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                if let body = try? res.content.decode(ModelListResponse.self) {
                    #expect(body.data.allSatisfy { $0.object == "model" })
                }
            }
        }
    }

    @Test("falls back to empty list when service throws")
    func fallsBackToEmptyListWhenServiceThrows() async throws {
        let mock = MockFoundationModelListable(behavior: .failure(MockListError()))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                #expect(body?.data.isEmpty == true)
            }
        }
    }

    @Test("falls back to empty list when service returns empty array")
    func fallsBackToEmptyListWhenServiceReturnsEmpty() async throws {
        let mock = MockFoundationModelListable(behavior: .empty)
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                let body = try? res.content.decode(ModelListResponse.self)
                #expect(body?.data.isEmpty == true)
            }
        }
    }

    @Test("returns 200 when service throws")
    func returns200WhenServiceThrows() async throws {
        let mock = MockFoundationModelListable(behavior: .failure(MockListError()))
        try await withApp({ app in
            try app.register(collection: ModelsController(foundationModelListable: mock))
        }) { app in
            try await app.test(.GET, "/v1/models") { res async in
                #expect(res.status == .ok)
            }
        }
    }
}
