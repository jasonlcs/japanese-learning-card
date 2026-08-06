import Foundation

/// V2 sync coordinator.  It keeps the existing semantic 3-way merge but
/// transports only changed logical items instead of a monolithic snapshot.
public actor SyncCoordinatorV2 {
    public enum SyncError: Error, Sendable, Equatable {
        case pushFailed(String)
        case pullFailed(String)
        case mergeFailed(String)
        case migrationFailed(String)
    }

    private let transport: CloudKitV2Transport
    private let legacyTransport: CloudKitTransport?
    private let store: AppStore
    private let stateStore: CloudKitV2SyncStateStore
    private let conflictStore: ConflictStore

    public init(
        transport: CloudKitV2Transport,
        store: AppStore,
        stateStore: CloudKitV2SyncStateStore,
        conflictStore: ConflictStore,
        legacyTransport: CloudKitTransport? = nil
    ) {
        self.transport = transport
        self.legacyTransport = legacyTransport
        self.store = store
        self.stateStore = stateStore
        self.conflictStore = conflictStore
    }

    public func pushIfNeeded() async throws {
        do {
            // Pull first so a push triggered by a local edit cannot overwrite
            // changes made by another device since the last poll.
            try await pullAndMerge()
            let local = await store.read()
            guard !local.isEffectivelyEmpty else { return }
            var state = try stateStore.load() ?? CloudKitV2SyncState()
            let currentItems = try CloudKitV2Codec.items(from: local)
            let baseItems = try state.baseSnapshot.map(CloudKitV2Codec.items(from:)) ?? []
            let baseByID = Dictionary(uniqueKeysWithValues: baseItems.map { ($0.id, $0) })
            let changed = currentItems.filter { baseByID[$0.id] != $0 }
            guard !changed.isEmpty else { return }

            try await transport.save(items: changed)
            var remoteByID = Dictionary(uniqueKeysWithValues: state.remoteItems.map { ($0.id, $0) })
            for item in changed { remoteByID[item.id] = item }
            state.remoteItems = Array(remoteByID.values)
            state.baseSnapshot = local
            state.migrationCompleted = true
            try stateStore.save(state)
        } catch {
            throw SyncError.pushFailed(String(describing: error))
        }
    }

    public func pullAndMerge() async throws {
        do {
            let local = await store.read()
            try await bootstrapIfNeeded(local: local)
            var state = try stateStore.load() ?? CloudKitV2SyncState()
            let changeSet: CloudKitV2ChangeSet
            do {
                changeSet = try await transport.fetchChanges(since: state.serverChangeToken)
            } catch CloudKitV2Transport.TransportError.backing(.changeTokenExpired) {
                state.remoteItems = []
                state.serverChangeToken = nil
                changeSet = try await transport.fetchChanges(since: nil)
            }

            var remoteByID = Dictionary(uniqueKeysWithValues: state.remoteItems.map { ($0.id, $0) })
            for item in changeSet.changedItems { remoteByID[item.id] = item }
            for recordName in changeSet.deletedRecordNames { remoteByID.removeValue(forKey: recordName) }

            let remoteItems = Array(remoteByID.values)
            guard !remoteItems.isEmpty else {
                state.serverChangeToken = changeSet.serverChangeToken
                state.remoteItems = remoteItems
                try stateStore.save(state)
                return
            }

            let remote = try CloudKitV2Codec.snapshot(from: remoteItems)
            let base = state.baseSnapshot
            let result = Merger.merge3Way(local: local, remote: remote, base: base)
            await conflictStore.replace(with: result.conflicts)
            try await store.update { snapshot in snapshot = result.snapshot }

            // The base is the remote state, not the merged local state.  Local
            // changes are intentionally left for the following push phase.
            state.remoteItems = remoteItems
            state.baseSnapshot = remote
            state.serverChangeToken = changeSet.serverChangeToken
            state.migrationCompleted = true
            try stateStore.save(state)
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.pullFailed(String(describing: error))
        }
    }

    private func bootstrapIfNeeded(local: AppSnapshot) async throws {
        try await transport.ensureZone()
        var state = try stateStore.load() ?? CloudKitV2SyncState()
        guard !state.migrationCompleted else { return }

        let initialChanges: CloudKitV2ChangeSet
        do {
            initialChanges = try await transport.fetchChanges(since: state.serverChangeToken)
        } catch CloudKitV2Transport.TransportError.backing(.changeTokenExpired) {
            initialChanges = try await transport.fetchChanges(since: nil)
        }

        var remoteByID = Dictionary(uniqueKeysWithValues: state.remoteItems.map { ($0.id, $0) })
        for item in initialChanges.changedItems { remoteByID[item.id] = item }
        for recordName in initialChanges.deletedRecordNames { remoteByID.removeValue(forKey: recordName) }

        var seed = local
        if !remoteByID.isEmpty {
            let remote = try CloudKitV2Codec.snapshot(from: Array(remoteByID.values))
            seed = local.isEffectivelyEmpty
                ? remote
                : Merger.merge3Way(local: local, remote: remote, base: nil).snapshot
        } else if let legacyTransport, let legacy = try? await legacyTransport.fetchLatest() {
            seed = local.isEffectivelyEmpty
                ? legacy.snapshot
                : Merger.merge3Way(local: local, remote: legacy.snapshot, base: nil).snapshot
        }

        let seedItems = try CloudKitV2Codec.items(from: seed)
        if !seedItems.isEmpty {
            try await transport.save(items: seedItems)
        }
        state.remoteItems = Array(Dictionary(uniqueKeysWithValues: seedItems.map { ($0.id, $0) }).values)
        state.baseSnapshot = seed
        state.serverChangeToken = initialChanges.serverChangeToken
        state.migrationCompleted = true
        try stateStore.save(state)
    }
}
