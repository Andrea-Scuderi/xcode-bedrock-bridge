import Testing
import Foundation
@testable import App

@Suite("AnthropicToolResultContent")
struct AnthropicToolResultContentTests {

    private func decode(_ json: String) throws -> AnthropicToolResultContent {
        try JSONDecoder().decode(AnthropicToolResultContent.self, from: Data(json.utf8))
    }

    @Test("decodes plain string as .text case")
    func decodesPlainStringAsText() throws {
        let content = try decode("\"result text\"")
        if case .text(let t) = content {
            #expect(t == "result text")
        } else {
            Issue.record("Expected .text case")
        }
    }

    @Test("decodes array as .blocks case")
    func decodesArrayAsBlocks() throws {
        let content = try decode("[{\"type\":\"text\",\"text\":\"result\"}]")
        if case .blocks(let blocks) = content {
            #expect(blocks.count == 1)
        } else {
            Issue.record("Expected .blocks case")
        }
    }

    @Test("asText from .text case returns the string")
    func asTextFromTextCase() {
        #expect(AnthropicToolResultContent.text("hello").asText == "hello")
    }

    @Test("asText from .blocks case joins all text values")
    func asTextFromBlocksJoinsTexts() {
        let content = AnthropicToolResultContent.blocks([
            AnthropicContentBlock.text("part one"),
            AnthropicContentBlock.text("part two"),
        ])
        #expect(content.asText == "part onepart two")
    }
}
