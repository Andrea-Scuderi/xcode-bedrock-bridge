import Testing
import Vapor
@testable import App

// Local error types whose type names contain the substrings that
// BedrockService.httpStatus(for:) inspects via String(describing: type(of: error)).
private struct ThrottlingError: Error {}
private struct ValidationError: Error {}
private struct AccessDeniedError: Error {}
private struct ResourceNotFoundError: Error {}
private struct ModelNotFoundError: Error {}
private struct ServiceUnavailableError: Error {}
private struct UnknownBedrockError: Error {}

@Suite("BedrockService Error Mapping")
struct BedrockServiceErrorMappingTests {

    @Test("Throttling error maps to 429 Too Many Requests")
    func throttlingErrorMapsToTooManyRequests() {
        #expect(BedrockService.httpStatus(for: ThrottlingError()) == .tooManyRequests)
    }

    @Test("Validation error maps to 400 Bad Request")
    func validationErrorMapsToBadRequest() {
        #expect(BedrockService.httpStatus(for: ValidationError()) == .badRequest)
    }

    @Test("AccessDenied error maps to 401 Unauthorized")
    func accessDeniedErrorMapsToUnauthorized() {
        #expect(BedrockService.httpStatus(for: AccessDeniedError()) == .unauthorized)
    }

    @Test("ResourceNotFound error maps to 404 Not Found")
    func resourceNotFoundErrorMapsToNotFound() {
        #expect(BedrockService.httpStatus(for: ResourceNotFoundError()) == .notFound)
    }

    @Test("ModelNotFound error maps to 404 Not Found")
    func modelNotFoundErrorMapsToNotFound() {
        #expect(BedrockService.httpStatus(for: ModelNotFoundError()) == .notFound)
    }

    @Test("ServiceUnavailable error maps to 503 Service Unavailable")
    func serviceUnavailableErrorMapsToServiceUnavailable() {
        #expect(BedrockService.httpStatus(for: ServiceUnavailableError()) == .serviceUnavailable)
    }

    @Test("unknown error maps to 500 Internal Server Error")
    func unknownErrorMapsToInternalServerError() {
        #expect(BedrockService.httpStatus(for: UnknownBedrockError()) == .internalServerError)
    }
}
