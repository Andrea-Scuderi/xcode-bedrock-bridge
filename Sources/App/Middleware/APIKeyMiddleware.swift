import Vapor

struct APIKeyMiddleware: AsyncMiddleware {
    let requiredKey: String

    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        // Check x-api-key header first, then Authorization: Bearer <key>.
        // Both comparisons use a timing-safe byte-by-byte XOR to prevent
        // key reconstruction via response-timing analysis.
        if let key = request.headers["x-api-key"].first, timingSafeEqual(key, requiredKey) {
            return try await next.respond(to: request)
        }
        if let authHeader = request.headers[.authorization].first {
            // RFC 7235: authentication scheme names are case-insensitive.
            let lower = authHeader.lowercased()
            if lower.hasPrefix("bearer ") {
                let key = String(authHeader.dropFirst("bearer ".count))
                if timingSafeEqual(key, requiredKey) {
                    return try await next.respond(to: request)
                }
            }
        }
        throw Abort(.unauthorized, reason: "Invalid or missing API key")
    }
}

/// Compares two strings in constant time (with respect to content) to prevent
/// timing-based key recovery attacks. Returns `true` only when both strings are
/// identical in length and content.
private func timingSafeEqual(_ a: String, _ b: String) -> Bool {
    let aBytes = Array(a.utf8)
    let bBytes = Array(b.utf8)
    guard aBytes.count == bBytes.count else { return false }
    return zip(aBytes, bBytes).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}
