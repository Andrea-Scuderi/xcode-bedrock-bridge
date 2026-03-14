import Vapor

/// Converts any thrown error into an OpenAI-compatible JSON error body:
/// `{ "error": { "message": "...", "type": "...", "param": null, "code": null } }`
struct OpenAIErrorMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        do {
            return try await next.respond(to: request)
        } catch let abort as AbortError {
            return errorResponse(status: abort.status, message: abort.reason)
        } catch {
            return errorResponse(status: .internalServerError, message: "An unexpected error occurred.")
        }
    }

    private func errorResponse(status: HTTPResponseStatus, message: String) -> Response {
        let detail = OpenAIErrorDetail(
            message: message,
            type: errorType(for: status),
            param: nil,
            code: nil
        )
        let body = OpenAIErrorResponse(error: detail)
        let response = Response(status: status)
        response.headers.contentType = .json
        try? response.content.encode(body, as: .json)
        return response
    }

    private func errorType(for status: HTTPResponseStatus) -> String {
        switch status.code {
        case 400: return "invalid_request_error"
        case 401: return "authentication_error"
        case 403: return "permission_error"
        case 404: return "not_found_error"
        case 413: return "invalid_request_error"
        case 422: return "invalid_request_error"
        case 429: return "rate_limit_error"
        default:  return status.code >= 500 ? "server_error" : "invalid_request_error"
        }
    }
}
