import Foundation

/// 把 provider profile 的 keychain reference 從舊制(preset 名稱、"default"、
/// 手動輸入值)統一遷移成新制「reference 一律等於 profile id」。
///
/// 遷移順序:
/// 1. 逐一把舊 reference 底下的 API key 複製到新 reference(新位置已有 key 就不覆蓋)。
/// 2. 全部 profile 都改寫完成後,才刪除已無 profile 引用的舊 keychain 項目。
///
/// 搬移失敗(keychain 錯誤)的 profile 會保留舊 reference,下次啟動重試,
/// 不會弄丟已儲存的 key。整段操作可重複執行(idempotent)。
public enum ProviderKeychainMigration {
    public static func needsMigration(_ settings: AppSettings) -> Bool {
        settings.providerProfiles.contains { $0.config.apiKeyKeychainRef != $0.keychainReference }
    }

    /// 回傳遷移後的 settings;完全不需要遷移時回傳 nil。
    public static func migrate(settings: AppSettings, secretStore: SecretStore) -> AppSettings? {
        var settings = settings
        settings.normalizeProviderProfiles()
        guard needsMigration(settings) else { return nil }

        var retiredReferences: Set<String> = []
        for index in settings.providerProfiles.indices {
            let profile = settings.providerProfiles[index]
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
            settings.providerProfiles[index].config.apiKeyKeychainRef = newReference
            settings.providerProfiles[index].updatedAt = Date()
            retiredReferences.insert(oldReference)
        }

        let stillReferenced = Set(settings.providerProfiles.map(\.config.apiKeyKeychainRef))
        for reference in retiredReferences.subtracting(stillReferenced) {
            try? secretStore.deleteAPIKey(reference: reference)
        }

        settings.normalizeProviderProfiles()
        return settings
    }
}
