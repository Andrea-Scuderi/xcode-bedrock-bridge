import Testing
import Foundation
@testable import App

@Suite("FoundationModelInfo")
struct FoundationModelInfoTests {

    // MARK: - Helpers

    private func decode(_ json: String) throws -> FoundationModelInfo {
        let data = Data(json.utf8)
        return try JSONDecoder().decode(FoundationModelInfo.self, from: data)
    }

    private func decodeList(_ json: String) throws -> [FoundationModelInfo] {
        struct Wrapper: Codable { let modelSummaries: [FoundationModelInfo] }
        let data = Data(json.utf8)
        return try JSONDecoder().decode(Wrapper.self, from: data).modelSummaries
    }

    // MARK: - isActive

    @Test("ACTIVE lifecycle status sets isActive true")
    func activeStatusSetsIsActiveTrue() throws {
        let model = try decode("""
        {
            "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
            "modelLifecycle": { "status": "ACTIVE" }
        }
        """)
        #expect(model.isActive == true)
    }

    @Test("LEGACY lifecycle status sets isActive false")
    func legacyStatusSetsIsActiveFalse() throws {
        let model = try decode("""
        {
            "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
            "modelLifecycle": { "status": "LEGACY" }
        }
        """)
        #expect(model.isActive == false)
    }

    @Test("missing modelLifecycle sets isActive false")
    func missingLifecycleSetsIsActiveFalse() throws {
        let model = try decode("""
        { "modelId": "anthropic.claude-3-haiku-20240307-v1:0" }
        """)
        #expect(model.isActive == false)
    }

    // MARK: - inputModalities / outputModalities

    @Test("inputModalities decoded correctly")
    func inputModalitiesDecoded() throws {
        let model = try decode("""
        {
            "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
            "inputModalities": ["TEXT", "IMAGE"],
            "modelLifecycle": { "status": "ACTIVE" }
        }
        """)
        #expect(model.inputModalities == ["TEXT", "IMAGE"])
    }

    @Test("outputModalities decoded correctly")
    func outputModalitiesDecoded() throws {
        let model = try decode("""
        {
            "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
            "outputModalities": ["TEXT"],
            "modelLifecycle": { "status": "ACTIVE" }
        }
        """)
        #expect(model.outputModalities == ["TEXT"])
    }

    @Test("missing inputModalities defaults to empty array")
    func missingInputModalitiesDefaultsToEmpty() throws {
        let model = try decode("""
        { "modelId": "anthropic.claude-3-haiku-20240307-v1:0" }
        """)
        #expect(model.inputModalities == [])
    }

    @Test("missing outputModalities defaults to empty array")
    func missingOutputModalitiesDefaultsToEmpty() throws {
        let model = try decode("""
        { "modelId": "anthropic.claude-3-haiku-20240307-v1:0" }
        """)
        #expect(model.outputModalities == [])
    }

    // MARK: - responseStreamingSupported

    @Test("responseStreamingSupported true decoded correctly")
    func responseStreamingSupportedTrue() throws {
        let model = try decode("""
        {
            "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
            "responseStreamingSupported": true
        }
        """)
        #expect(model.responseStreamingSupported == true)
    }

    @Test("responseStreamingSupported false decoded correctly")
    func responseStreamingSupportedFalse() throws {
        let model = try decode("""
        {
            "modelId": "cohere.embed-english-v3",
            "responseStreamingSupported": false
        }
        """)
        #expect(model.responseStreamingSupported == false)
    }

    @Test("missing responseStreamingSupported is nil")
    func missingResponseStreamingSupportedIsNil() throws {
        let model = try decode("""
        { "modelId": "amazon.titan-embed-image-v1" }
        """)
        #expect(model.responseStreamingSupported == nil)
    }

    // MARK: - Full entry (matching aws bedrock list-foundation-models output)

    @Test("full AWS response entry decoded correctly")
    func fullEntryDecoded() throws {
        let model = try decode("""
        {
            "modelArn": "arn:aws:bedrock:eu-west-2::foundation-model/anthropic.claude-sonnet-4-5-20250929-v1:0",
            "modelId": "anthropic.claude-sonnet-4-5-20250929-v1:0",
            "modelName": "Claude Sonnet 4.5",
            "providerName": "Anthropic",
            "inputModalities": ["TEXT", "IMAGE"],
            "outputModalities": ["TEXT"],
            "responseStreamingSupported": true,
            "customizationsSupported": [],
            "inferenceTypesSupported": ["INFERENCE_PROFILE"],
            "modelLifecycle": { "status": "ACTIVE" }
        }
        """)
        #expect(model.modelId == "anthropic.claude-sonnet-4-5-20250929-v1:0")
        #expect(model.modelName == "Claude Sonnet 4.5")
        #expect(model.providerName == "Anthropic")
        #expect(model.isActive == true)
        #expect(model.inputModalities == ["TEXT", "IMAGE"])
        #expect(model.outputModalities == ["TEXT"])
        #expect(model.responseStreamingSupported == true)
    }

    @Test("modelSummaries wrapper decoded correctly")
    func modelSummariesWrapperDecoded() throws {
        let models = try decodeList("""
        {
            "modelSummaries": [
                {
                    "modelId": "anthropic.claude-3-haiku-20240307-v1:0",
                    "modelName": "Claude 3 Haiku",
                    "inputModalities": ["TEXT", "IMAGE"],
                    "outputModalities": ["TEXT"],
                    "responseStreamingSupported": true,
                    "modelLifecycle": { "status": "ACTIVE" }
                },
                {
                    "modelId": "cohere.embed-english-v3",
                    "modelName": "Embed English",
                    "inputModalities": ["TEXT"],
                    "outputModalities": ["EMBEDDING"],
                    "responseStreamingSupported": false,
                    "modelLifecycle": { "status": "ACTIVE" }
                }
            ]
        }
        """)
        #expect(models.count == 2)
        #expect(models[0].modelId == "anthropic.claude-3-haiku-20240307-v1:0")
        #expect(models[0].inputModalities == ["TEXT", "IMAGE"])
        #expect(models[1].outputModalities == ["EMBEDDING"])
        #expect(models[1].responseStreamingSupported == false)
    }

    // MARK: - inferenceTypesSupported / supportsInferenceProfile

    @Test("inferenceTypesSupported decoded correctly")
    func inferenceTypesSupportedDecoded() throws {
        let model = try decode("""
        {
            "modelId": "anthropic.claude-sonnet-4-5-20250929-v1:0",
            "inferenceTypesSupported": ["INFERENCE_PROFILE"],
            "modelLifecycle": { "status": "ACTIVE" }
        }
        """)
        #expect(model.inferenceTypesSupported == ["INFERENCE_PROFILE"])
        #expect(model.supportsInferenceProfile == true)
    }

    @Test("ON_DEMAND only does not support inference profile")
    func onDemandOnlyDoesNotSupportInferenceProfile() throws {
        let model = try decode("""
        {
            "modelId": "cohere.embed-english-v3",
            "inferenceTypesSupported": ["ON_DEMAND"]
        }
        """)
        #expect(model.supportsInferenceProfile == false)
    }

    @Test("mixed ON_DEMAND and INFERENCE_PROFILE supports inference profile")
    func mixedInferenceTypesSupportsProfile() throws {
        let model = try decode("""
        {
            "modelId": "amazon.nova-pro-v1:0",
            "inferenceTypesSupported": ["ON_DEMAND", "INFERENCE_PROFILE"]
        }
        """)
        #expect(model.supportsInferenceProfile == true)
    }

    @Test("missing inferenceTypesSupported defaults to empty and no profile support")
    func missingInferenceTypesSupportedDefaults() throws {
        let model = try decode("""
        { "modelId": "amazon.titan-embed-image-v1" }
        """)
        #expect(model.inferenceTypesSupported == [])
        #expect(model.supportsInferenceProfile == false)
    }

    // MARK: - Memberwise init

    @Test("memberwise init sets all fields correctly")
    func memberwiseInitSetsFields() {
        let model = FoundationModelInfo(
            modelId: "us.amazon.nova-pro-v1:0",
            modelName: "Nova Pro",
            providerName: "Amazon",
            isActive: true,
            inputModalities: ["TEXT", "IMAGE", "VIDEO"],
            outputModalities: ["TEXT"],
            responseStreamingSupported: true
        )
        #expect(model.modelId == "us.amazon.nova-pro-v1:0")
        #expect(model.modelName == "Nova Pro")
        #expect(model.isActive == true)
        #expect(model.inputModalities == ["TEXT", "IMAGE", "VIDEO"])
        #expect(model.outputModalities == ["TEXT"])
        #expect(model.responseStreamingSupported == true)
    }

    @Test("memberwise init defaults produce empty modalities and nil streaming")
    func memberwiseInitDefaults() {
        let model = FoundationModelInfo(modelId: "some.model", isActive: true)
        #expect(model.inputModalities == [])
        #expect(model.outputModalities == [])
        #expect(model.responseStreamingSupported == nil)
    }
}
