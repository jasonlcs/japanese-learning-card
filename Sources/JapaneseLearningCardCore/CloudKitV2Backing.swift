import CloudKit
import Foundation

/// CloudKit implementation for the V2 item protocol.
public final class CKContainerV2Backing: CloudKitV2Backing, @unchecked Sendable {
    private let container: CKContainer
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let maxItemsPerBatch = 50

    public init(
        container: CKContainer = CKContainer(identifier: CloudKitSchema.containerIdentifier),
        zoneID: CKRecordZone.ID = CKRecordZone.ID(zoneName: CloudKitV2Schema.zoneName)
    ) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.zoneID = zoneID
    }

    public func ensureZone() async throws {
        do {
            let result = try await database.recordZones(for: [zoneID])[zoneID]
            if case .success = result { return }
            if case .failure(let error) = result,
               let ckError = error as? CKError,
               ckError.code != .zoneNotFound {
                throw Self.translate(ckError)
            }
        } catch let error as CloudKitV2BackingError {
            throw error
        } catch let error as CKError where error.code != .zoneNotFound {
            throw Self.translate(error)
        } catch {
            // A missing custom zone is expected on the first V2 launch.
        }

        do {
            _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Another device may have created it concurrently, or production
            // CloudKit may report an existing zone as a rejected save.
            return
        } catch let error as CKError {
            throw Self.translate(error)
        } catch {
            throw CloudKitV2BackingError.unknown(String(describing: error))
        }
    }

    public func fetchChanges(since token: Data?) async throws -> CloudKitV2ChangeSet {
        var serverToken = try Self.decodeToken(token)
        var changedItems: [CloudKitV2Item] = []
        var deletedRecordNames: [String] = []
        var moreComing = true

        while moreComing {
            do {
                let result = try await database.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: serverToken,
                    desiredKeys: nil,
                    resultsLimit: 100
                )
                for modificationResult in result.modificationResultsByID.values {
                    switch modificationResult {
                    case .success(let modification):
                        changedItems.append(try Self.item(from: modification.record))
                    case .failure(let error):
                        throw Self.translate(error)
                    }
                }
                deletedRecordNames.append(contentsOf: result.deletions.map { $0.recordID.recordName })
                serverToken = result.changeToken
                moreComing = result.moreComing
            } catch let error as CloudKitV2BackingError {
                throw error
            } catch let error as CKError {
                throw Self.translate(error)
            } catch {
                throw CloudKitV2BackingError.unknown(String(describing: error))
            }
        }

        return CloudKitV2ChangeSet(
            changedItems: changedItems,
            deletedRecordNames: deletedRecordNames,
            serverChangeToken: try Self.encodeToken(serverToken)
        )
    }

    public func save(items: [CloudKitV2Item]) async throws {
        for batch in strideBatches(items, size: maxItemsPerBatch) {
            var temporaryFiles: [URL] = []
            defer {
                for fileURL in temporaryFiles {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            do {
                let records = try batch.map { item -> CKRecord in
                    if let payload = item.payload, payload.count > CloudKitV2Item.maxInlinePayloadBytes {
                        throw CloudKitV2BackingError.recordTooLarge
                    }
                    let record = CKRecord(
                        recordType: CloudKitV2Schema.recordType,
                        recordID: CKRecord.ID(recordName: item.id, zoneID: zoneID)
                    )
                    record[CloudKitV2Schema.Field.kind.rawValue] = item.kind.rawValue as NSString
                    record[CloudKitV2Schema.Field.entityID.rawValue] = item.entityID as NSString
                    record[CloudKitV2Schema.Field.schemaVersion.rawValue] = NSNumber(value: item.schemaVersion)
                    record[CloudKitV2Schema.Field.updatedAt.rawValue] = item.updatedAt as NSDate
                    record[CloudKitV2Schema.Field.isDeleted.rawValue] = NSNumber(value: item.isDeleted)

                    if let payload = item.payload {
                        record[CloudKitV2Schema.Field.payload.rawValue] = payload as NSData
                    } else {
                        record[CloudKitV2Schema.Field.payload.rawValue] = nil
                    }

                    if let assetData = item.assetData {
                        let fileURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("jlc-v2-\(UUID().uuidString).asset")
                        try assetData.write(to: fileURL, options: [.atomic])
                        temporaryFiles.append(fileURL)
                        record[CloudKitV2Schema.Field.contentAsset.rawValue] = CKAsset(fileURL: fileURL)
                    } else {
                        record[CloudKitV2Schema.Field.contentAsset.rawValue] = nil
                    }
                    return record
                }

                let result = try await database.modifyRecords(
                    saving: records,
                    deleting: [],
                    savePolicy: .changedKeys,
                    atomically: false
                )
                let failures = result.saveResults.compactMap { id, saveResult -> String? in
                    if case .failure(let error) = saveResult {
                        return "\(id.recordName): \(error)"
                    }
                    return nil
                }
                if !failures.isEmpty {
                    throw CloudKitV2BackingError.partialBatchFailure(failures.joined(separator: "; "))
                }
            } catch let error as CloudKitV2BackingError {
                throw error
            } catch let error as CKError {
                throw Self.translate(error)
            } catch {
                throw CloudKitV2BackingError.unknown(String(describing: error))
            }
        }
    }

    public func registerSubscription() async throws {
        do {
            _ = try await database.subscription(for: CloudKitV2Schema.subscriptionID)
            return
        } catch let error as CKError where error.code != .unknownItem {
            throw Self.translate(error)
        } catch {
            // Missing subscription: create it below.
        }

        let subscription = CKRecordZoneSubscription(
            zoneID: zoneID,
            subscriptionID: CloudKitV2Schema.subscriptionID
        )
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
        } catch let error as CKError where error.code == .serverRejectedRequest || error.code == .invalidArguments {
            return
        } catch let error as CKError {
            throw Self.translate(error)
        } catch {
            throw CloudKitV2BackingError.unknown(String(describing: error))
        }
    }

    private static func item(from record: CKRecord) throws -> CloudKitV2Item {
        guard let kindValue = record[CloudKitV2Schema.Field.kind.rawValue] as? String,
              let kind = CloudKitV2ItemKind(rawValue: kindValue),
              let entityID = record[CloudKitV2Schema.Field.entityID.rawValue] as? String,
              let schemaVersion = record[CloudKitV2Schema.Field.schemaVersion.rawValue] as? NSNumber,
              let updatedAt = record[CloudKitV2Schema.Field.updatedAt.rawValue] as? Date,
              let isDeleted = record[CloudKitV2Schema.Field.isDeleted.rawValue] as? NSNumber else {
            throw CloudKitV2BackingError.unknown("V2 Record 欄位不完整: \(record.recordID.recordName)")
        }
        let payload = record[CloudKitV2Schema.Field.payload.rawValue] as? Data
        var assetData: Data?
        if let asset = record[CloudKitV2Schema.Field.contentAsset.rawValue] as? CKAsset,
           let fileURL = asset.fileURL {
            assetData = try Data(contentsOf: fileURL)
        }
        return CloudKitV2Item(
            kind: kind,
            entityID: entityID,
            schemaVersion: schemaVersion.intValue,
            updatedAt: updatedAt,
            isDeleted: isDeleted.boolValue,
            payload: payload,
            assetData: assetData
        )
    }

    private static func encodeToken(_ token: CKServerChangeToken?) throws -> Data? {
        guard let token else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private static func decodeToken(_ data: Data?) throws -> CKServerChangeToken? {
        guard let data else { return nil }
        return try NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private static func translate(_ error: Error) -> CloudKitV2BackingError {
        guard let error = error as? CKError else {
            return .unknown(String(describing: error))
        }
        switch error.code {
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .notAuthenticated:
            return .notAuthenticated
        case .limitExceeded:
            return .recordTooLarge
        case .changeTokenExpired:
            return .changeTokenExpired
        default:
            return .unknown(String(describing: error))
        }
    }

    private func strideBatches<T>(_ values: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [values] }
        var batches: [[T]] = []
        var index = 0
        while index < values.count {
            let end = min(index + size, values.count)
            batches.append(Array(values[index..<end]))
            index = end
        }
        return batches
    }
}
