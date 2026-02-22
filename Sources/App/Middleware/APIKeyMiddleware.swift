import Vapor

struct APIKeyMiddleware: AsyncMiddleware {
    let requiredKey: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Check x-api-key header first, then Authorization: Bearer <key>
        if let key = request.headers["x-api-key"].first, key == requiredKey {
            return try await next.respond(to: request)
        }
        if let authHeader = request.headers[.authorization].first,
           authHeader.hasPrefix("Bearer "),
           authHeader.dropFirst("Bearer ".count) == requiredKey
        {
            return try await next.respond(to: request)
        }
        throw Abort(.unauthorized, reason: "Invalid or missing API key")
    }
}
