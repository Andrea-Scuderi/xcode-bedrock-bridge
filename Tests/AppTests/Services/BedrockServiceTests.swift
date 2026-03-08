import Testing
import SotoCore
import Vapor
@testable import App

// MARK: - Helpers

private func awsError(_ code: String) -> Error {
    AWSResponseError(errorCode: code)
}

@Suite("BedrockService Error Mapping")
struct BedrockServiceErrorMappingTests {

    @Test("Throttling error maps to 429 Too Many Requests")
    func throttlingErrorMapsToTooManyRequests() {
        #expect(BedrockService.httpStatus(for: awsError("ThrottlingException")) == .tooManyRequests)
    }

    @Test("Validation error maps to 400 Bad Request")
    func validationErrorMapsToBadRequest() {
        #expect(BedrockService.httpStatus(for: awsError("ValidationException")) == .badRequest)
    }

    @Test("AccessDenied error maps to 403 Forbidden")
    func accessDeniedErrorMapsToForbidden() {
        #expect(BedrockService.httpStatus(for: awsError("AccessDeniedException")) == .forbidden)
    }

    @Test("ResourceNotFound error maps to 404 Not Found")
    func resourceNotFoundErrorMapsToNotFound() {
        #expect(BedrockService.httpStatus(for: awsError("ResourceNotFoundException")) == .notFound)
    }

    @Test("ModelNotFound error maps to 404 Not Found")
    func modelNotFoundErrorMapsToNotFound() {
        #expect(BedrockService.httpStatus(for: awsError("ModelNotFoundException")) == .notFound)
    }

    @Test("ServiceUnavailable error maps to 503 Service Unavailable")
    func serviceUnavailableErrorMapsToServiceUnavailable() {
        #expect(BedrockService.httpStatus(for: awsError("ServiceUnavailableException")) == .serviceUnavailable)
    }

    @Test("unknown error maps to 500 Internal Server Error")
    func unknownErrorMapsToInternalServerError() {
        struct UnknownError: Error {}
        #expect(BedrockService.httpStatus(for: UnknownError()) == .internalServerError)
    }

    @Test("clientSafeReason returns HTTP status phrase, not internal error detail")
    func clientSafeReasonReturnsStatusPhrase() {
        #expect(BedrockService.clientSafeReason(for: awsError("ThrottlingException")) == "Too Many Requests")
        #expect(BedrockService.clientSafeReason(for: awsError("AccessDeniedException")) == "Forbidden")
        struct UnknownError: Error {}
        #expect(BedrockService.clientSafeReason(for: UnknownError()) == "Internal Server Error")
    }
}
