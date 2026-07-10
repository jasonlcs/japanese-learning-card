import XCTest
@testable import JapaneseLearningCardCore

final class ProviderModelInfoTests: XCTestCase {
    func testSupportedVoicesMarksModelAsTTS() throws {
        let json = """
        {
          "data": [
            {
              "id": "openai/gpt-4o-mini-tts-2025-12-15",
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["audio"],
                "modality": "text->audio"
              },
              "supported_voices": ["alloy", "coral"]
            },
            {
              "id": "openai/gpt-5.2",
              "architecture": {
                "input_modalities": ["text"],
                "output_modalities": ["text"],
                "modality": "text->text"
              },
              "supported_voices": null
            }
          ]
        }
        """

        let response = try JSONDecoder().decode(ProviderModelsResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.ttsModelIDs, ["openai/gpt-4o-mini-tts-2025-12-15"])
    }

    func testAudioOutputModalityWithoutVoicesDoesNotMarkModelAsTTS() {
        let model = ProviderModelInfo(
            id: "openai/gpt-audio-mini",
            architecture: .init(modality: "text->audio", outputModalities: ["audio"]),
            supportedVoices: nil
        )

        XCTAssertFalse(model.supportsTextToSpeech)
    }

    func testMusicGenerationAudioModelDoesNotMarkModelAsTTS() {
        let model = ProviderModelInfo(
            id: "google/lyria-3-clip-preview",
            architecture: .init(modality: "text->audio", outputModalities: ["audio"]),
            supportedVoices: nil
        )

        XCTAssertFalse(model.supportsTextToSpeech)
    }

    func testKnownTTSNamingRemainsFallbackForOpenAICompatibleLists() {
        let model = ProviderModelInfo(id: "tts-1-hd")

        XCTAssertTrue(model.supportsTextToSpeech)
    }

    func testTextOnlyModelDoesNotSupportTTS() {
        let model = ProviderModelInfo(
            id: "openai/gpt-5.2",
            architecture: .init(modality: "text->text", outputModalities: ["text"]),
            supportedVoices: nil
        )

        XCTAssertFalse(model.supportsTextToSpeech)
    }

    func testDiagnosticsReportsAudioOutputSeparatelyFromTTS() {
        let response = ProviderModelsResponse(data: [
            ProviderModelInfo(
                id: "openai/gpt-audio-mini",
                architecture: .init(modality: "text->audio", outputModalities: ["audio"]),
                supportedVoices: nil
            ),
            ProviderModelInfo(id: "openai/gpt-5.2")
        ])

        let diagnostics = response.ttsDiagnostics

        XCTAssertEqual(diagnostics.totalCount, 2)
        XCTAssertEqual(diagnostics.supportedVoicesCount, 0)
        XCTAssertEqual(diagnostics.likelyTTSNameCount, 0)
        XCTAssertEqual(diagnostics.audioOutputCount, 1)
        XCTAssertEqual(diagnostics.audioOutputExamples, ["openai/gpt-audio-mini"])
    }
}
