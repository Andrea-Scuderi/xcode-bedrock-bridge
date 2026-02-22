import XCTVapor
@testable import App

final class RouteTests: XCTestCase {

    // MARK: - GET /v1/models

    func testModelsEndpointReturnsListWithoutAuth() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            XCTAssertEqual(res.status, .ok)
            let body = try? res.content.decode(ModelListResponse.self)
            XCTAssertNotNil(body)
            XCTAssertEqual(body?.object, "list")
            XCTAssertGreaterThan(body?.data.count ?? 0, 0)
        }
    }

    func testModelsEndpointReturnsExpectedModels() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        try app.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            XCTAssertEqual(res.status, .ok)
            if let body = try? res.content.decode(ModelListResponse.self) {
                let ids = body.data.map(\.id)
                XCTAssertTrue(ids.contains("us.anthropic.claude-3-5-sonnet-20241022-v2:0"))
                XCTAssertTrue(ids.contains("us.anthropic.claude-3-haiku-20240307-v1:0"))
            }
        }
    }

    // MARK: - API Key Middleware

    func testAPIKeyMiddlewareBlocksMissingKey() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }

    func testAPIKeyMiddlewareAllowsValidXAPIKey() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secret"]) { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testAPIKeyMiddlewareAllowsValidBearerToken() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer secret")

        try await app.test(.GET, "/v1/models", headers: headers) { res async in
            XCTAssertEqual(res.status, .ok)
        }
    }

    func testAPIKeyMiddlewareBlocksWrongKey() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }

        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models", headers: ["x-api-key": "wrong"]) { res async in
            XCTAssertEqual(res.status, .unauthorized)
        }
    }
}
