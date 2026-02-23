import Testing
import VaporTesting
@testable import App

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

    @Test("response contains expected model IDs")
    func responseContainsExpectedModelIDs() async throws {
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

    @Test("all models have owned_by anthropic")
    func allModelsHaveOwnedByAnthropic() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            if let body = try? res.content.decode(ModelListResponse.self) {
                #expect(body.data.allSatisfy { $0.ownedBy == "anthropic" })
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
