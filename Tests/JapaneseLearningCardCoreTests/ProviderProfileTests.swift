import XCTest
@testable import JapaneseLearningCardCore

final class ProviderProfileTests: XCTestCase {
    func testOldSettingsDecodeCreatesProviderProfileFromProviderConfig() throws {
        let json = """
        {
          "providerConfig": {
            "preset": "googleAIStudio",
            "baseURL": "https://generativelanguage.googleapis.com/v1beta/openai",
            "model": "gemma-4-26b-a4b-it",
            "apiKeyKeychainRef": "googleAIStudio",
            "extraHeaders": {},
            "structuredOutput": "off"
          }
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.providerProfiles.count, 1)
        XCTAssertEqual(settings.activeProviderProfileId, settings.providerProfiles[0].id)
        XCTAssertEqual(settings.providerProfiles[0].name, ProviderPreset.googleAIStudio.displayName)
        XCTAssertEqual(settings.providerProfiles[0].config.model, "gemma-4-26b-a4b-it")
        XCTAssertEqual(settings.providerProfiles[0].lastVerificationStatus, .unverified)
        XCTAssertEqual(settings.providerConfig, settings.providerProfiles[0].config)
    }

    func testSettingsNormalizeFallsBackToFirstProfileWhenActiveIdIsInvalid() {
        let first = ProviderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "OpenAI",
            config: ProviderConfig(preset: .openAI, model: "gpt-4.1-mini", apiKeyKeychainRef: "openAI")
        )
        let second = ProviderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Gemma",
            config: ProviderConfig(preset: .googleAIStudio, model: "gemma-4-26b-a4b-it", apiKeyKeychainRef: "googleAIStudio")
        )

        var settings = AppSettings(
            providerConfig: second.config,
            providerProfiles: [first, second],
            activeProviderProfileId: UUID(uuidString: "00000000-0000-0000-0000-00000000FFFF")!
        )
        settings.normalizeProviderProfiles()

        XCTAssertEqual(settings.activeProviderProfileId, first.id)
        XCTAssertEqual(settings.providerConfig, first.config)
    }

    func testDefaultSettingsCreatesDefaultProfile() {
        let settings = AppSettings()

        XCTAssertEqual(settings.providerProfiles.count, 1)
        XCTAssertEqual(settings.activeProviderProfileId, settings.providerProfiles[0].id)
        XCTAssertEqual(settings.providerConfig, settings.providerProfiles[0].config)
    }
}
