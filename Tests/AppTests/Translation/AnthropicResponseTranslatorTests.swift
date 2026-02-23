import Testing
import SotoBedrockRuntime
@testable import App

@Suite("AnthropicResponseTranslator")
struct AnthropicResponseTranslatorTests {

    let translator = AnthropicResponseTranslator()

    @Test("stop reason .endTurn maps to 'end_turn'")
    func stopReasonEndTurnMapsToEndTurn() {
        #expect(translator.translateStopReason(.endTurn) == "end_turn")
    }

    @Test("stop reason .maxTokens maps to 'max_tokens'")
    func stopReasonMaxTokensMapsToMaxTokens() {
        #expect(translator.translateStopReason(.maxTokens) == "max_tokens")
    }

    @Test("stop reason .toolUse maps to 'tool_use'")
    func stopReasonToolUseMapsToToolUse() {
        #expect(translator.translateStopReason(.toolUse) == "tool_use")
    }

    @Test("nil stop reason defaults to 'end_turn'")
    func nilStopReasonDefaultsToEndTurn() {
        #expect(translator.translateStopReason(nil) == "end_turn")
    }

    @Test("ping SSE has correct format")
    func pingSSEHasCorrectFormat() {
        let sse = translator.pingSSE()
        #expect(sse == "event: ping\ndata: {\"type\":\"ping\"}\n\n")
    }

    @Test("messageStartSSE contains message ID and model")
    func messageStartSSEContainsMessageIDAndModel() {
        let sse = translator.messageStartSSE(messageID: "msg_abc123", model: "claude-sonnet")
        #expect(sse.contains("msg_abc123"))
        #expect(sse.contains("claude-sonnet"))
    }

    @Test("messageStartSSE escapes double quotes in model name")
    func messageStartSSEEscapesSpecialCharsInModel() {
        let sse = translator.messageStartSSE(messageID: "msg_test", model: "model\"with\"quotes")
        #expect(sse.contains("model\\\"with\\\"quotes"))
    }

    @Test("finalSSE contains both message_delta and message_stop events")
    func finalSSEContainsBothEvents() {
        let sse = translator.finalSSE(stopReason: "end_turn", outputTokens: 10)
        #expect(sse.contains("event: message_delta"))
        #expect(sse.contains("event: message_stop"))
    }

    @Test("finalSSE embeds stop reason in data")
    func finalSSEStopReasonEmbedded() {
        let sse = translator.finalSSE(stopReason: "max_tokens", outputTokens: 0)
        #expect(sse.contains("max_tokens"))
    }

    @Test("finalSSE embeds output token count")
    func finalSSEOutputTokensEmbedded() {
        let sse = translator.finalSSE(stopReason: "end_turn", outputTokens: 42)
        #expect(sse.contains("\"output_tokens\":42"))
    }

    @Test("messageStartSSE escapes newline in model name")
    func jsonEscapeNewlineViaSSE() {
        let sse = translator.messageStartSSE(messageID: "msg_id", model: "model\nname")
        #expect(sse.contains("model\\nname"))
    }

    @Test("messageStartSSE escapes backslash in model name")
    func jsonEscapeBackslashViaSSE() {
        let sse = translator.messageStartSSE(messageID: "msg_id", model: "model\\name")
        #expect(sse.contains("model\\\\name"))
    }
}
