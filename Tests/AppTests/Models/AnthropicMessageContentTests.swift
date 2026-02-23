import Testing
import Foundation
@testable import App

@Suite("AnthropicMessageContent Decoding")
struct AnthropicMessageContentTests {

    private func decode(_ json: String) throws -> AnthropicMessageContent {
        try JSONDecoder().decode(AnthropicMessageContent.self, from: Data(json.utf8))
    }

    @Test("decodes plain string as .text case")
    func decodesStringAsText() throws {
        let content = try decode("\"hello\"")
        if case .text(let t) = content {
            #expect(t == "hello")
        } else {
            Issue.record("Expected .text case")
        }
    }

    @Test("decodes array as .blocks case")
    func decodesArrayAsBlocks() throws {
        let content = try decode("[{\"type\":\"text\",\"text\":\"hi\"}]")
        if case .blocks(let blocks) = content {
            #expect(blocks.count == 1)
            #expect(blocks[0].text == "hi")
        } else {
            Issue.record("Expected .blocks case")
        }
    }

    @Test("blocks property from .text case wraps in single text block")
    func blocksPropertyFromTextCase() {
        let content = AnthropicMessageContent.text("x")
        #expect(content.blocks.count == 1)
        #expect(content.blocks[0].text == "x")
    }

    @Test("blocks property from .blocks case returns all blocks")
    func blocksPropertyFromBlocksCase() {
        let content = AnthropicMessageContent.blocks([
            AnthropicContentBlock.text("first"),
            AnthropicContentBlock.text("second"),
        ])
        #expect(content.blocks.count == 2)
    }
}
