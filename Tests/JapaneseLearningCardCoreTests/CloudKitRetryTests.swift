import XCTest
import CloudKit
@testable import JapaneseLearningCardCore

private final class TestRecorder: @unchecked Sendable {
    var attempts = 0
    var sleepCalls: [UInt64] = []
    private let lock = NSLock()

    func recordAttempt() -> Int {
        lock.lock()
        defer { lock.unlock() }
        attempts += 1
        return attempts
    }

    func recordSleep(_ nanoseconds: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        sleepCalls.append(nanoseconds)
    }

    var recordedAttempts: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    var recordedSleepCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleepCalls.count
    }
}

final class CloudKitRetryTests: XCTestCase {
    func testTranslateCKErrorServiceUnavailable() {
        let userInfo: [String: Any] = [CKErrorRetryAfterKey: NSNumber(value: 4.0)]
        let ckError = CKError(_nsError: NSError(domain: CKErrorDomain, code: CKError.serviceUnavailable.rawValue, userInfo: userInfo))

        let translated = CKContainerV2Backing.translate(ckError)
        XCTAssertEqual(translated, .serviceUnavailable(retryAfter: 4.0))
    }

    func testTranslateCKErrorRequestRateLimited() {
        let userInfo: [String: Any] = [CKErrorRetryAfterKey: NSNumber(value: 10.0)]
        let ckError = CKError(_nsError: NSError(domain: CKErrorDomain, code: CKError.requestRateLimited.rawValue, userInfo: userInfo))

        let translated = CKContainerV2Backing.translate(ckError)
        XCTAssertEqual(translated, .rateLimited(retryAfter: 10.0))
    }

    func testTranslateCKErrorZoneBusy() {
        let ckError = CKError(_nsError: NSError(domain: CKErrorDomain, code: CKError.zoneBusy.rawValue, userInfo: nil))

        let translated = CKContainerV2Backing.translate(ckError)
        XCTAssertEqual(translated, .zoneBusy)
    }

    func testWithRetrySucceedsAfterTransientErrors() async throws {
        let recorder = TestRecorder()

        let result = try await CKContainerV2Backing.withRetry(
            maxAttempts: 3,
            sleeper: { recorder.recordSleep($0) }
        ) { () -> String in
            let attempt = recorder.recordAttempt()
            if attempt < 3 {
                throw CloudKitV2BackingError.serviceUnavailable(retryAfter: 0.1)
            }
            return "success"
        }

        XCTAssertEqual(result, "success")
        XCTAssertEqual(recorder.recordedAttempts, 3)
        XCTAssertEqual(recorder.recordedSleepCount, 2)
    }

    func testWithRetryThrowsWhenExceedingMaxAttempts() async throws {
        let recorder = TestRecorder()

        do {
            _ = try await CKContainerV2Backing.withRetry(
                maxAttempts: 3,
                sleeper: { recorder.recordSleep($0) }
            ) { () -> String in
                _ = recorder.recordAttempt()
                throw CloudKitV2BackingError.serviceUnavailable(retryAfter: 0.1)
            }
            XCTFail("Should have thrown")
        } catch let error as CloudKitV2BackingError {
            XCTAssertEqual(error, .serviceUnavailable(retryAfter: 0.1))
            XCTAssertEqual(recorder.recordedAttempts, 3)
            XCTAssertEqual(recorder.recordedSleepCount, 2)
        }
    }

    func testWithRetryDoesNotRetryNonTransientErrors() async throws {
        let recorder = TestRecorder()

        do {
            _ = try await CKContainerV2Backing.withRetry(
                maxAttempts: 3,
                sleeper: { recorder.recordSleep($0) }
            ) { () -> String in
                _ = recorder.recordAttempt()
                throw CloudKitV2BackingError.quotaExceeded
            }
            XCTFail("Should have thrown")
        } catch let error as CloudKitV2BackingError {
            XCTAssertEqual(error, .quotaExceeded)
            XCTAssertEqual(recorder.recordedAttempts, 1)
            XCTAssertEqual(recorder.recordedSleepCount, 0)
        }
    }
}
