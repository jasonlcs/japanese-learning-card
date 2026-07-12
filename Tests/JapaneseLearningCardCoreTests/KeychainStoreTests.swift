import Security
import XCTest
@testable import JapaneseLearningCardCore

final class KeychainStoreTests: XCTestCase {
    func testBaseQueryUsesDataProtectionKeychain() {
        let query = KeychainStore.makeBaseQuery(reference: "default")

        XCTAssertEqual(query[kSecAttrAccount as String] as? String, "default")
        XCTAssertEqual(query[kSecAttrService as String] as? String, "JapaneseLearningCard.OpenAICompatibleAPI")
        XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
    }
}
