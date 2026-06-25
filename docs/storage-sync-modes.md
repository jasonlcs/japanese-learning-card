# Storage and Sync Modes Development Specification

This document defines the planned storage architecture for Japanese Learning Card. The app should support three user-selectable storage modes:

1. Local Only
2. iCloud Drive Folder
3. CloudKit

The main product goal is that user learning data can remain unrelated to the developer's own servers or databases. CloudKit remains available as an optional advanced sync backend, while local-first storage becomes a first-class option.

## Goals

- Support three storage modes as explicit user choices.
- Ensure only one storage mode is active at a time.
- Keep upper-level app logic independent from storage implementation details.
- Preserve the current CloudKit design as one storage provider.
- Add local file storage and iCloud Drive folder storage.
- Avoid developer-managed backend storage for personal learning data.
- Allow clear migration, import, and export between modes.
- Avoid automatic deletion of source data when switching modes.

## Non-Goals

- Do not implement real-time bidirectional sync between CloudKit and iCloud Drive.
- Do not use CloudKit Public Database for personal learning data.
- Do not introduce a developer-owned API or PostgreSQL database for user learning data.
- Do not rely on a single large JSON file for all user data.
- Do not delete old data automatically during migration.

## Storage Modes

### Local Only

Local Only stores all user data on the current Mac.

Recommended default path:

```text
~/Library/Application Support/JapaneseLearningCard/
```

For sandboxed app builds, use the app container equivalent:

```text
~/Library/Containers/<bundle-id>/Data/Library/Application Support/JapaneseLearningCard/
```

Characteristics:

- No sync.
- No iCloud account required.
- No CloudKit entitlement required.
- Data remains on the current Mac.
- Supports manual backup, export, and import.

### iCloud Drive Folder

iCloud Drive Folder stores data in a user-selected folder. If the selected folder is inside iCloud Drive, macOS and iCloud Drive handle file synchronization.

Example path:

```text
~/Library/Mobile Documents/com~apple~CloudDocs/JapaneseLearningCard/
```

Characteristics:

- App reads and writes normal local files.
- iCloud Drive sync is handled by macOS.
- App does not directly call CloudKit in this mode.
- User chooses the data location.
- If the folder is inside iCloud Drive, two Macs signed into the same Apple ID can sync data through iCloud Drive.
- Sync is file-based, not database-based.

Important risks:

- Two Macs editing the same file at the same time can create file conflicts.
- iCloud Drive sync is not guaranteed to be immediate.
- Duplicate or conflict files may appear.
- App must be able to rescan and reconcile the folder.

### CloudKit

CloudKit uses the existing CloudKit design and should store personal learning data in the user's CloudKit Private Database.

Characteristics:

- Requires CloudKit entitlement and Apple Developer configuration.
- Requires the user to be signed into iCloud.
- CloudKit container is managed under the developer account.
- Personal learning data should use Private Database, not Public Database.
- Data should not be copied to a developer-owned backend.
- App must handle account state, offline state, schema migration, and sync errors.

## Storage Abstraction

Upper-level application code should not directly depend on file storage, iCloud Drive folder storage, or CloudKit.

Introduce a common storage interface:

```swift
protocol UserDataStore {
    func loadSnapshot() async throws -> AppDataSnapshot
    func saveCard(_ card: Card) async throws
    func deleteCard(id: String) async throws
    func saveReview(_ review: ReviewRecord) async throws
    func getCards() async throws -> [Card]
    func getReviewHistory() async throws -> [ReviewRecord]
    func getHealth() async throws -> DataStoreHealth
}
```

Expected implementations:

```text
LocalFileDataStore
ICloudDriveFolderDataStore
CloudKitDataStore
```

Storage mode settings:

```swift
enum StorageMode: String, Codable {
    case localOnly
    case iCloudDriveFolder
    case cloudKit
}

struct StorageSettings: Codable {
    var mode: StorageMode
    var localDataPath: String?
    var iCloudDriveFolderPath: String?
    var cloudKitContainerId: String?
}
```

Factory:

```swift
protocol UserDataStoreFactory {
    func create(settings: StorageSettings) throws -> UserDataStore
}
```

The factory is responsible for creating the active data store based on saved settings. The rest of the app should work through `UserDataStore`.

## File Storage Format

For Local Only and iCloud Drive Folder modes, use a multi-file layout instead of one large JSON file.

Recommended structure:

```text
JapaneseLearningCard/
  manifest.json
  cards/
    <card-id>.json
  decks/
    <deck-id>.json
  reviews/
    2026/
      06/
        review-events-2026-06-25.jsonl
  media/
    images/
    audio/
  indexes/
    cards-index.json
  backups/
  conflicts/
```

Reasons:

- A single card update only rewrites one card file.
- Review history can be append-only.
- Concurrent edits from multiple Macs have a smaller conflict surface.
- File-level repair and migration are easier.
- Media files can be stored naturally.

### manifest.json

```json
{
  "app": "JapaneseLearningCard",
  "schemaVersion": 1,
  "createdAt": "2026-06-25T00:00:00Z",
  "lastOpenedAt": "2026-06-25T00:00:00Z",
  "storageId": "uuid",
  "deviceId": "uuid"
}
```

### cards/<card-id>.json

```json
{
  "id": "card-uuid",
  "deckId": "deck-uuid",
  "front": "日本語",
  "back": "Japanese language",
  "reading": "にほんご",
  "tags": ["noun", "basic"],
  "createdAt": "2026-06-25T00:00:00Z",
  "updatedAt": "2026-06-25T00:00:00Z",
  "deletedAt": null
}
```

### reviews/YYYY/MM/review-events-YYYY-MM-DD.jsonl

```jsonl
{"id":"event-uuid","cardId":"card-uuid","rating":3,"reviewedAt":"2026-06-25T10:20:00Z","deviceId":"device-uuid"}
{"id":"event-uuid","cardId":"card-uuid","rating":4,"reviewedAt":"2026-06-25T10:25:00Z","deviceId":"device-uuid"}
```

Review events should be append-only and deduplicated by event id during reads.

## CloudKit Data Model

CloudKit does not need to mirror the exact file layout. It should use record types that match app domain objects.

Recommended record types:

```text
Deck
Card
ReviewEvent
UserSettings
```

Card fields:

```text
id: String
deckId: String
front: String
back: String
reading: String
tags: [String]
createdAt: Date
updatedAt: Date
deletedAt: Date?
deviceId: String
```

ReviewEvent fields:

```text
id: String
cardId: String
rating: Int
reviewedAt: Date
deviceId: String
```

CloudKit rules:

- Use Private Database for personal learning data.
- Use stable logical ids.
- Prefer logical delete with `deletedAt`.
- Keep `updatedAt` and `deviceId` on mutable records.
- Treat review events as append-only records.

## Sync and Conflict Handling

### Local Only

No sync is required.

Required behavior:

- Validate data folder on startup.
- Create missing directories.
- Support backup and restore.
- Detect corrupted JSON files and report them clearly.

### iCloud Drive Folder

Minimum behavior:

- Scan data folder on app startup.
- Rescan when app enters foreground.
- Watch for file changes when possible.
- Before writing a card, check whether the on-disk version is newer than the in-memory version.
- Detect duplicated or conflicting card files.
- Deduplicate review events by event id.

Conflict strategy:

```text
New vs new: keep both if ids differ.
Edit vs edit: keep latest as active, move older version to conflicts/.
Delete vs edit: mark as conflict and ask user to choose.
Review events: merge by event id.
```

Conflict folder:

```text
conflicts/
  cards/
    <card-id>-<timestamp>-<device-id>.json
```

Settings UI should show unresolved conflicts:

```text
2 sync conflicts found
[Review] [Resolve Later]
```

### CloudKit

Required behavior:

- Check iCloud account availability.
- Check CloudKit container availability.
- Handle offline mode.
- Queue local changes when offline if supported by current app architecture.
- Retry transient sync errors.
- Expose sync health to settings UI.
- Avoid storing personal learning data in Public Database.

## Mode Switching and Migration

Only one storage mode may be the active writer at any time.

Supported migrations:

```text
Local Only -> iCloud Drive Folder
Local Only -> CloudKit
iCloud Drive Folder -> Local Only
iCloud Drive Folder -> CloudKit
CloudKit -> Local Only
CloudKit -> iCloud Drive Folder
```

Migration flow:

1. Load a complete snapshot from the current data store.
2. Create and validate the target data location.
3. Write the complete snapshot to the target data store.
4. Read back the target snapshot.
5. Validate record counts and checksums.
6. Ask the user to confirm the switch.
7. Update `StorageSettings.mode`.
8. Keep source data in place.

Migration UI copy:

```text
Your data will be copied to the new storage location. The original data will not be deleted. After switching, the app will only use the new storage mode.
```

Rollback:

- If migration validation fails, keep the original mode active.
- Do not partially switch settings.
- Leave incomplete target data in a recoverable folder or clean it only after explicit confirmation.

## Settings UI Requirements

Add a "Data and Sync" settings screen.

Current status should show:

```text
Current storage mode: iCloud Drive Folder
Data location: /Users/.../iCloud Drive/JapaneseLearningCard
Last checked: 2026-06-25 10:30
Status: Healthy
```

Mode choices:

```text
Local Only
Data is stored only on this Mac.

iCloud Drive Folder
Data is stored in a folder you choose. If the folder is inside iCloud Drive, it syncs through your Apple ID.

CloudKit
Data syncs through Apple CloudKit. Requires iCloud sign-in.
```

Actions:

```text
Choose Folder
Export Data
Import Data
Switch Storage Mode
Check Sync Status
Resolve Conflicts
Create Backup
Restore Backup
```

## Privacy Copy

Recommended user-facing copy:

```text
Local Only: Your data is stored only on this Mac.

iCloud Drive Folder: Your data is stored in the folder you choose. If that folder is inside iCloud Drive, it syncs through your Apple ID. The developer does not receive or manage this data.

CloudKit: Your data syncs through Apple CloudKit in your iCloud private database. The developer manages the app's CloudKit container, but does not use a developer-owned server to store your learning data.
```

## Development Phases

### Phase 1: Storage Abstraction

- Introduce `UserDataStore`.
- Introduce `StorageSettings`.
- Introduce `UserDataStoreFactory`.
- Wrap current CloudKit code as `CloudKitDataStore`.
- Remove direct CloudKit dependency from upper-level app logic.

### Phase 2: Local Only

- Implement `LocalFileDataStore`.
- Create file/folder schema.
- Support cards, decks, and review history.
- Support basic schema versioning.
- Add import/export.
- Add backup and restore.

### Phase 3: iCloud Drive Folder

- Implement `ICloudDriveFolderDataStore`.
- Add folder picker.
- Add folder validation.
- Add file rescanning and change detection.
- Add conflict detection.
- Add conflict UI entry points.

### Phase 4: Migration

- Implement snapshot export from all data stores.
- Implement snapshot import into all data stores.
- Add migration validation.
- Add checksum or equivalent integrity verification.
- Support all six mode-switch paths.
- Keep source data after migration.

### Phase 5: CloudKit Hardening

- Confirm all personal data uses Private Database.
- Add health reporting.
- Add account-state handling.
- Add offline and retry behavior where needed.
- Add schema migration strategy.

## Recommended Default Product Behavior

Recommended mode positioning:

```text
Default: Local Only
Recommended sync: iCloud Drive Folder
Advanced sync: CloudKit
```

This keeps the app local-first while still supporting CloudKit for users who want deeper Apple-platform sync behavior.
