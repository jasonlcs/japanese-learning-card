import Foundation

public struct ProviderModelsResponse: Codable, Equatable, Sendable {
    public var data: [ProviderModelInfo]?

    public init(data: [ProviderModelInfo]? = nil) {
        self.data = data
    }

    public var models: [ProviderModelInfo] {
        data ?? []
    }

    public var sortedModelIDs: [String] {
        models.map(\.id).sorted()
    }

    public var ttsModelIDs: [String] {
        models.filter(\.supportsTextToSpeech).map(\.id).sorted()
    }

    public var ttsDiagnostics: ProviderModelDiagnostics {
        ProviderModelDiagnostics(models: models)
    }
}

public struct ProviderModelDiagnostics: Equatable, Sendable {
    public var totalCount: Int
    public var supportedVoicesCount: Int
    public var likelyTTSNameCount: Int
    public var audioOutputCount: Int
    public var audioOutputExamples: [String]

    public init(models: [ProviderModelInfo]) {
        totalCount = models.count
        supportedVoicesCount = models.filter { $0.supportedVoices != nil }.count
        likelyTTSNameCount = models.filter { $0.hasLikelyTTSName }.count
        let audioOutputModels = models.filter(\.hasAudioOutput)
        audioOutputCount = audioOutputModels.count
        audioOutputExamples = Array(audioOutputModels.map(\.id).sorted().prefix(3))
    }

    public var summary: String {
        var parts = [
            "總模型 \(totalCount)",
            "supported_voices \(supportedVoicesCount)",
            "名稱含 tts/speech \(likelyTTSNameCount)",
            "audio output \(audioOutputCount)"
        ]
        if !audioOutputExamples.isEmpty {
            parts.append("audio 範例：\(audioOutputExamples.joined(separator: ", "))")
        }
        return parts.joined(separator: "；")
    }
}

public struct ProviderModelInfo: Codable, Equatable, Sendable {
    public struct Architecture: Codable, Equatable, Sendable {
        public var modality: String?
        public var inputModalities: [String]?
        public var outputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case modality
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
        }

        public init(modality: String? = nil, inputModalities: [String]? = nil, outputModalities: [String]? = nil) {
            self.modality = modality
            self.inputModalities = inputModalities
            self.outputModalities = outputModalities
        }
    }

    public var id: String
    public var architecture: Architecture?
    public var supportedVoices: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case architecture
        case supportedVoices = "supported_voices"
    }

    public init(id: String, architecture: Architecture? = nil, supportedVoices: [String]? = nil) {
        self.id = id
        self.architecture = architecture
        self.supportedVoices = supportedVoices
    }

    public var supportsTextToSpeech: Bool {
        if supportedVoices != nil {
            return true
        }

        return hasLikelyTTSName
    }

    public var hasLikelyTTSName: Bool {
        Self.isLikelyTTSModelID(id)
    }

    public var hasAudioOutput: Bool {
        if let outputModalities = architecture?.outputModalities,
           outputModalities.contains(where: { modality in
               modality.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "audio"
           }) {
            return true
        }
        return architecture?.modality?.lowercased().contains("->audio") == true
    }

    private static func isLikelyTTSModelID(_ id: String) -> Bool {
        let normalized = id.lowercased()
        return normalized.contains("tts") || normalized.contains("speech")
    }
}
