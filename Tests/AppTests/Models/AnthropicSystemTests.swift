import Testing
import Foundation
@testable import App

@Suite("AnthropicSystem Decoding")
struct AnthropicSystemTests {

    private func decode(_ json: String) throws -> AnthropicSystem {
        try JSONDecoder().decode(AnthropicSystem.self, from: Data(json.utf8))
    }

    @Test("decodes plain string as .text case")
    func decodesStringAsText() throws {
        let system = try decode("\"Be helpful\"")
        if case .text(let t) = system {
            #expect(t == "Be helpful")
        } else {
            Issue.record("Expected .text case")
        }
    }

    @Test("decodes array of text blocks as .blocks case")
    func decodesArrayOfBlocks() throws {
        let system = try decode("[{\"type\":\"text\",\"text\":\"Block\"}]")
        if case .blocks(let blocks) = system {
            #expect(blocks.count == 1)
        } else {
            Issue.record("Expected .blocks case")
        }
    }

    @Test("plainText from .text case returns the string")
    func plainTextFromTextCase() {
        #expect(AnthropicSystem.text("hello").plainText == "hello")
    }

    @Test("plainText from single block returns block text")
    func plainTextFromSingleBlock() {
        let system = AnthropicSystem.blocks([AnthropicTextBlock(type: "text", text: "content")])
        #expect(system.plainText == "content")
    }

    @Test("plainText from multiple blocks joins with newline")
    func plainTextFromMultipleBlocksJoinsWithNewline() {
        let system = AnthropicSystem.blocks([
            AnthropicTextBlock(type: "text", text: "Line one"),
            AnthropicTextBlock(type: "text", text: "Line two"),
        ])
        #expect(system.plainText == "Line one\nLine two")
    }
}
