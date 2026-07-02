import XCTest
@testable import JapaneseLearningCardCore

private final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    var storage: [String: String] = [:]

    func saveAPIKey(_ apiKey: String, reference: String) throws {
        storage[reference] = apiKey
    }

    func apiKey(reference: String) throws -> String? {
        storage[reference]
    }

    func deleteAPIKey(reference: String) throws {
        storage[reference] = nil
    }
}

final class ProviderKeychainMigrationTests: XCTestCase {
    func testKeychainReferenceEqualsProfileId() {
        let id = UUID(uuidString: "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")!
        let profile = ProviderProfile(id: id, name: "Test", config: ProviderConfig())

        XCTAssertEqual(profile.keychainReference, "0A1B2C3D-4E5F-6071-8293-A4B5C6D7E8F9")
        XCTAssertEqual(ProviderProfile.keychainReference(for: id), profile.keychainReference)
    }

    func testSanitizedKeychainReferenceKeepsAllowedCharacters() {
        XCTAssertEqual(
            ProviderProfile.sanitizedKeychainReference("abc-XYZ.019"),
            "abc-XYZ.019"
        )
    }

    func testSanitizedKeychainReferenceEscapesSpecialCharacters() {
        // 空白、斜線、underscore 都會轉成 `_XX`(UTF-8 byte 的大寫 hex)。
        XCTAssertEqual(ProviderProfile.sanitizedKeychainReference("a b"), "a_20b")
        XCTAssertEqual(ProviderProfile.sanitizedKeychainReference("a/b"), "a_2Fb")
        XCTAssertEqual(ProviderProfile.sanitizedKeychainReference("a_b"), "a_5Fb")
        // 非 ASCII 逐 byte 轉義。
        XCTAssertEqual(ProviderProfile.sanitizedKeychainReference("卡"), "_E5_8D_A1")
    }

    func testSanitizedKeychainReferenceIsInjectiveForEscapeCollisions() {
        // "a_b" 與 "a_5Fb" 若不轉義 `_` 會撞出同一個結果;轉義後必須不同。
        XCTAssertNotEqual(
            ProviderProfile.sanitizedKeychainReference("a_b"),
            ProviderProfile.sanitizedKeychainReference("a_5Fb")
        )
    }

    func testMigrationMovesKeysToProfileIdReferences() throws {
        let first = ProviderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "OpenAI",
            config: ProviderConfig(preset: .openAI, apiKeyKeychainRef: "openAI")
        )
        let second = ProviderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            name: "Gemma",
            config: ProviderConfig(preset: .googleAIStudio, apiKeyKeychainRef: "default")
        )
        var settings = AppSettings(
            providerConfig: first.config,
            providerProfiles: [first, second],
            activeProviderProfileId: first.id
        )
        settings.normalizeProviderProfiles()

        let secretStore = InMemorySecretStore()
        secretStore.storage = ["openAI": "sk-first", "default": "sk-second"]

        let migrated = try XCTUnwrap(ProviderKeychainMigration.migrate(settings: settings, secretStore: secretStore))

        for profile in migrated.providerProfiles {
            XCTAssertEqual(profile.config.apiKeyKeychainRef, profile.keychainReference)
        }
        XCTAssertEqual(secretStore.storage[first.keychainReference], "sk-first")
        XCTAssertEqual(secretStore.storage[second.keychainReference], "sk-second")
        // 舊 reference 搬移完成後刪除。
        XCTAssertNil(secretStore.storage["openAI"])
        XCTAssertNil(secretStore.storage["default"])
        // active profile 的 config 會同步回 providerConfig,LLMClient 才讀得到新 reference。
        XCTAssertEqual(migrated.providerConfig.apiKeyKeychainRef, first.keychainReference)
    }

    func testMigrationReturnsNilWhenAlreadyMigrated() {
        var settings = AppSettings()
        settings.normalizeProviderProfiles()
        for index in settings.providerProfiles.indices {
            settings.providerProfiles[index].config.apiKeyKeychainRef =
                settings.providerProfiles[index].keychainReference
        }
        settings.normalizeProviderProfiles()

        XCTAssertNil(ProviderKeychainMigration.migrate(settings: settings, secretStore: InMemorySecretStore()))
    }

    func testMigrationKeepsExistingKeyAtNewReference() throws {
        let profile = ProviderProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            name: "OpenAI",
            config: ProviderConfig(preset: .openAI, apiKeyKeychainRef: "openAI")
        )
        var settings = AppSettings(
            providerConfig: profile.config,
            providerProfiles: [profile],
            activeProviderProfileId: profile.id
        )
        settings.normalizeProviderProfiles()

        // 新位置已經有 key(例如上次搬到一半),不可被舊值覆蓋。
        let secretStore = InMemorySecretStore()
        secretStore.storage = ["openAI": "sk-old", profile.keychainReference: "sk-new"]

        let migrated = try XCTUnwrap(ProviderKeychainMigration.migrate(settings: settings, secretStore: secretStore))

        XCTAssertEqual(secretStore.storage[profile.keychainReference], "sk-new")
        XCTAssertNil(secretStore.storage["openAI"])
        XCTAssertEqual(migrated.providerProfiles[0].config.apiKeyKeychainRef, profile.keychainReference)
    }
}
