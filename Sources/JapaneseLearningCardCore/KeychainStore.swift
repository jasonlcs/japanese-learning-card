import Foundation
import Security

public enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            "Keychain operation failed with status \(status)."
        case .invalidData:
            "Keychain item data is invalid."
        }
    }
}

public protocol SecretStore: Sendable {
    func saveAPIKey(_ apiKey: String, reference: String) throws
    func apiKey(reference: String) throws -> String?
    func deleteAPIKey(reference: String) throws
}

public struct KeychainStore: SecretStore {
    private let service = "JapaneseLearningCard.OpenAICompatibleAPI"

    public init() {}

    public func saveAPIKey(_ apiKey: String, reference: String) throws {
        let data = Data(apiKey.utf8)
        let query = baseQuery(reference: reference)
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData as String] = data
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    public func apiKey(reference: String) throws -> String? {
        var query = baseQuery(reference: reference)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let apiKey = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return apiKey
    }

    public func deleteAPIKey(reference: String) throws {
        let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }

    private func baseQuery(reference: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: reference
        ]
    }
}
