import Testing
import Foundation
@testable import App

@Suite("ChatMessage Custom Decoding")
struct ChatMessageDecodingTests {

    private func decode(_ json: String) throws -> ChatMessage {
        try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))
    }

    @Test("decodes plain string content")
    func decodesPlainStringContent() throws {
        let msg = try decode("{\"role\":\"user\",\"content\":\"Hello\"}")
        #expect(msg.content == "Hello")
    }

    @Test("decodes content parts array joining text parts")
    func decodesContentPartsArray() throws {
        let json = "{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Hi\"},{\"type\":\"text\",\"text\":\" there\"}]}"
        #expect(try decode(json).content == "Hi there")
    }

    @Test("content parts skips non-text types")
    func contentPartsSkipsNonTextTypes() throws {
        let json = "{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"text\":null},{\"type\":\"text\",\"text\":\"Hi\"}]}"
        #expect(try decode(json).content == "Hi")
    }

    @Test("decodes role correctly")
    func decodesRoleCorrectly() throws {
        #expect(try decode("{\"role\":\"assistant\",\"content\":\"Howdy\"}").role == "assistant")
    }

    @Test("content parts with all non-text types yields empty string")
    func contentPartsWithNilTextYieldsEmpty() throws {
        let json = "{\"role\":\"user\",\"content\":[{\"type\":\"image\"}]}"
        #expect(try decode(json).content == "")
    }
}
