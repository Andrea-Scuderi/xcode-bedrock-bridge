import Testing
import VaporTesting
@testable import App

@Suite("APIKeyMiddleware")
struct APIKeyMiddlewareTests {

    @Test("blocks missing key")
    func blocksMissingKey() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models") { res async in
            #expect(res.status == .unauthorized)
        }
    }

    @Test("allows valid x-api-key header")
    func allowsValidXAPIKey() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secret"]) { res async in
            #expect(res.status == .ok)
        }
    }

    @Test("allows valid Bearer token")
    func allowsValidBearerToken() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer secret")

        try await app.test(.GET, "/v1/models", headers: headers) { res async in
            #expect(res.status == .ok)
        }
    }

    @Test("blocks wrong x-api-key")
    func blocksWrongKey() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models", headers: ["x-api-key": "wrong"]) { res async in
            #expect(res.status == .unauthorized)
        }
    }

    @Test("blocks wrong Bearer value")
    func blocksBearerWithWrongValue() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "Bearer wrong")

        try await app.test(.GET, "/v1/models", headers: headers) { res async in
            #expect(res.status == .unauthorized)
        }
    }

    @Test("blocks Authorization without Bearer prefix")
    func blocksBearerWithoutPrefix() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "secret")

        try await app.test(.GET, "/v1/models", headers: headers) { res async in
            #expect(res.status == .unauthorized)
        }
    }

    @Test("allows lowercase bearer prefix (RFC 7235 case-insensitive scheme)")
    func allowsLowercaseBearerPrefix() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        var headers = HTTPHeaders()
        headers.add(name: .authorization, value: "bearer secret")

        try await app.test(.GET, "/v1/models", headers: headers) { res async in
            #expect(res.status == .ok)
        }
    }

    @Test("blocks key that differs only in last byte (timing-safe comparison)")
    func blocksKeyWithLastByteDifference() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secretA"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secretB"]) { res async in
            #expect(res.status == .unauthorized)
        }
    }

    @Test("blocks key with same prefix but longer length")
    func blocksKeyWithSamePrefixButLonger() async throws {
        let app = try await Application.make(.testing)
        defer { Task { try await app.asyncShutdown() } }
        let protected = app.grouped(APIKeyMiddleware(requiredKey: "secret"))
        try protected.register(collection: ModelsController())

        try await app.test(.GET, "/v1/models", headers: ["x-api-key": "secretXXX"]) { res async in
            #expect(res.status == .unauthorized)
        }
    }
}
