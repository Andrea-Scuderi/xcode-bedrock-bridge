import Testing
import Foundation
@testable import App

@Suite("JSONValue Coding")
struct JSONValueCodingTests {

    private func decode(_ json: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
    }

    @Test("decodes string literal")
    func decodesStringLiteral() throws {
        #expect(try decode("\"hello\"") == .string("hello"))
    }

    @Test("decodes integer as number")
    func decodesIntegerAsNumber() throws {
        #expect(try decode("42") == .number(42.0))
    }

    @Test("decodes double as number")
    func decodesDoubleAsNumber() throws {
        let value = try decode("3.14")
        if case .number(let d) = value {
            #expect(abs(d - 3.14) < 0.001)
        } else {
            Issue.record("Expected .number case, got \(value)")
        }
    }

    @Test("decodes boolean true")
    func decodesBooleanTrue() throws {
        #expect(try decode("true") == .bool(true))
    }

    @Test("decodes boolean false")
    func decodesBooleanFalse() throws {
        #expect(try decode("false") == .bool(false))
    }

    @Test("decodes null literal")
    func decodesNullLiteral() throws {
        #expect(try decode("null") == .null)
    }

    @Test("decodes array recursively")
    func decodesArrayRecursively() throws {
        #expect(try decode("[1,\"a\"]") == .array([.number(1.0), .string("a")]))
    }

    @Test("decodes object recursively")
    func decodesObjectRecursively() throws {
        #expect(try decode("{\"k\":true}") == .object(["k": .bool(true)]))
    }
}
