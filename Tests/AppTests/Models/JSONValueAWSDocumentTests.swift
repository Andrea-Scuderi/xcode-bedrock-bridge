import Testing
@testable import App

@Suite("JSONValue AWSDocument Conversion")
struct JSONValueAWSDocumentTests {

    @Test("null roundtrips through AWSDocument")
    func nullRoundtrips() {
        let original = JSONValue.null
        #expect(JSONValue.from(document: original.toAWSDocument()) == original)
    }

    @Test("bool roundtrips through AWSDocument")
    func boolRoundtrips() {
        let original = JSONValue.bool(true)
        #expect(JSONValue.from(document: original.toAWSDocument()) == original)
    }

    @Test("string roundtrips through AWSDocument")
    func stringRoundtrips() {
        let original = JSONValue.string("hello world")
        #expect(JSONValue.from(document: original.toAWSDocument()) == original)
    }

    @Test("double roundtrips through AWSDocument")
    func doubleRoundtrips() {
        let original = JSONValue.number(3.14)
        let roundtripped = JSONValue.from(document: original.toAWSDocument())
        if case .number(let d) = roundtripped {
            #expect(abs(d - 3.14) < 0.001)
        } else {
            Issue.record("Expected .number case, got \(roundtripped)")
        }
    }

    @Test("whole number stored as integer document and roundtrips to same value")
    func integerUsesIntegerDocument() {
        #expect(JSONValue.from(document: JSONValue.number(3.0).toAWSDocument()) == .number(3.0))
    }

    @Test("array roundtrips through AWSDocument")
    func arrayRoundtrips() {
        let original = JSONValue.array([.number(1.0), .string("a"), .bool(false)])
        #expect(JSONValue.from(document: original.toAWSDocument()) == original)
    }

    @Test("object roundtrips through AWSDocument")
    func objectRoundtrips() {
        let original = JSONValue.object(["x": .number(1.0), "y": .string("val")])
        #expect(JSONValue.from(document: original.toAWSDocument()) == original)
    }
}
