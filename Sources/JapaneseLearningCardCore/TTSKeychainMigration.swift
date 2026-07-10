import Foundation

/// 把 TTS API key 從舊制(不論選哪個 provider,都共用同一個 keychain 帳號
/// `AppSettings.legacyTTSKeychainReference`)搬進新制「每個 TTS profile 各自
/// 獨立的 keychain reference」。
///
/// 舊制下切換 TTS provider(例如先存 OpenAI、再存 Gemini)會讓後存的 key
/// 覆蓋掉前一個,導致切回 OpenAI 時實際送出的是 Gemini 的 key 而回 401。
/// 新制讓每個 profile 持有自己的 key,搬移邏輯與 `ProviderKeychainMigration`
/// 一致:只搬移、不覆蓋新位置已有的 key;失敗會留在舊 reference 等下次重試,
/// 全部搬完才刪除已無 profile 引用的舊 keychain 項目。整段操作可重複執行。
public enum TTSKeychainMigration {
    public static func needsMigration(_ settings: AppSettings) -> Bool {
        settings.ttsProviderProfiles.contains { $0.config.apiKeyKeychainRef != $0.keychainReference }
    }

    /// 回傳遷移後的 settings;完全不需要遷移時回傳 nil。
    public static func migrate(settings: AppSettings, secretStore: SecretStore) -> AppSettings? {
        var settings = settings
        settings.normalizeTTSProviderProfiles()
        guard needsMigration(settings) else { return nil }

        var retiredReferences: Set<String> = []
        for index in settings.ttsProviderProfiles.indices {
            let profile = settings.ttsProviderProfiles[index]
            let newReference = profile.keychainReference
            let oldReference = profile.config.apiKeyKeychainRef
            guard oldReference != newReference else { continue }
            do {
                if let key = try secretStore.apiKey(reference: oldReference), !key.isEmpty,
                   try !secretStore.hasAPIKey(reference: newReference) {
                    try secretStore.saveAPIKey(key, reference: newReference)
                }
            } catch {
                continue
            }
            settings.ttsProviderProfiles[index].config.apiKeyKeychainRef = newReference
            settings.ttsProviderProfiles[index].updatedAt = Date()
            retiredReferences.insert(oldReference)
        }

        let stillReferenced = Set(settings.ttsProviderProfiles.map(\.config.apiKeyKeychainRef))
        for reference in retiredReferences.subtracting(stillReferenced) {
            try? secretStore.deleteAPIKey(reference: reference)
        }

        settings.normalizeTTSProviderProfiles()
        return settings
    }
}
