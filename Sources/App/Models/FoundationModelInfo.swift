// MARK: - FoundationModelInfo

struct FoundationModelInfo: Sendable, Codable {
    let modelId: String
    let modelName: String?
    let providerName: String?
    let isActive: Bool
    let inputModalities: [String]
    let outputModalities: [String]
    let responseStreamingSupported: Bool?
    let inferenceTypesSupported: [String]

    /// True when the model supports cross-region inference profiles, meaning
    /// a `global.` prefix can be prepended to take advantage of Global inference.
    var supportsInferenceProfile: Bool {
        inferenceTypesSupported.contains("INFERENCE_PROFILE")
    }

    // MARK: - Memberwise init (used by BedrockService and tests)

    init(
        modelId: String,
        modelName: String? = nil,
        providerName: String? = nil,
        isActive: Bool = true,
        inputModalities: [String] = [],
        outputModalities: [String] = [],
        responseStreamingSupported: Bool? = nil,
        inferenceTypesSupported: [String] = []
    ) {
        self.modelId = modelId
        self.modelName = modelName
        self.providerName = providerName
        self.isActive = isActive
        self.inputModalities = inputModalities
        self.outputModalities = outputModalities
        self.responseStreamingSupported = responseStreamingSupported
        self.inferenceTypesSupported = inferenceTypesSupported
    }

    // MARK: - Codable (decodes raw `aws bedrock list-foundation-models` JSON)

    private struct ModelLifecycle: Codable {
        let status: String?
    }

    private enum CodingKeys: String, CodingKey {
        case modelId, modelName, providerName, modelLifecycle
        case inputModalities, outputModalities, responseStreamingSupported
        case inferenceTypesSupported
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        modelId = try c.decode(String.self, forKey: .modelId)
        modelName = try c.decodeIfPresent(String.self, forKey: .modelName)
        providerName = try c.decodeIfPresent(String.self, forKey: .providerName)
        let lifecycle = try c.decodeIfPresent(ModelLifecycle.self, forKey: .modelLifecycle)
        isActive = lifecycle?.status?.lowercased() == "active"
        inputModalities = try c.decodeIfPresent([String].self, forKey: .inputModalities) ?? []
        outputModalities = try c.decodeIfPresent([String].self, forKey: .outputModalities) ?? []
        responseStreamingSupported = try c.decodeIfPresent(Bool.self, forKey: .responseStreamingSupported)
        inferenceTypesSupported = try c.decodeIfPresent([String].self, forKey: .inferenceTypesSupported) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(modelId, forKey: .modelId)
        try c.encodeIfPresent(modelName, forKey: .modelName)
        try c.encodeIfPresent(providerName, forKey: .providerName)
        try c.encode(inputModalities, forKey: .inputModalities)
        try c.encode(outputModalities, forKey: .outputModalities)
        try c.encodeIfPresent(responseStreamingSupported, forKey: .responseStreamingSupported)
        try c.encode(inferenceTypesSupported, forKey: .inferenceTypesSupported)
    }
}
