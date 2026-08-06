import Foundation

public actor CloudKitV2Transport {
    public enum TransportError: Error, Sendable, Equatable {
        case backing(CloudKitV2BackingError)
        case encodingFailed
        case decodingFailed
    }

    private let backing: CloudKitV2Backing

    public init(backing: CloudKitV2Backing) {
        self.backing = backing
    }

    public func ensureZone() async throws {
        do {
            try await backing.ensureZone()
        } catch let error as CloudKitV2BackingError {
            throw TransportError.backing(error)
        } catch {
            throw TransportError.backing(.unknown(String(describing: error)))
        }
    }

    public func fetchChanges(since token: Data?) async throws -> CloudKitV2ChangeSet {
        do {
            return try await backing.fetchChanges(since: token)
        } catch let error as CloudKitV2BackingError {
            throw TransportError.backing(error)
        } catch {
            throw TransportError.backing(.unknown(String(describing: error)))
        }
    }

    public func save(items: [CloudKitV2Item]) async throws {
        do {
            try await backing.save(items: items)
        } catch let error as CloudKitV2BackingError {
            throw TransportError.backing(error)
        } catch {
            throw TransportError.backing(.unknown(String(describing: error)))
        }
    }

    public func ensureSubscriptionRegistered() async throws {
        do {
            try await backing.registerSubscription()
        } catch let error as CloudKitV2BackingError {
            throw TransportError.backing(error)
        } catch {
            throw TransportError.backing(.unknown(String(describing: error)))
        }
    }
}
