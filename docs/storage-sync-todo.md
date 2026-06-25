# Storage and Sync Modes TODO

This TODO list tracks implementation work for the three storage modes:

- Local Only
- iCloud Drive Folder
- CloudKit

## Phase 1: Storage Abstraction

- [ ] Audit current CloudKit usage and list all direct read/write call sites.
- [ ] Define `UserDataStore` protocol.
- [ ] Define `StorageMode`.
- [ ] Define `StorageSettings`.
- [ ] Define `DataStoreHealth`.
- [ ] Define `AppDataSnapshot`.
- [ ] Add `UserDataStoreFactory`.
- [ ] Wrap existing CloudKit code in `CloudKitDataStore`.
- [ ] Update app services/view models to depend on `UserDataStore`, not CloudKit directly.
- [ ] Add tests for factory selection by storage mode.

## Phase 2: File Data Format

- [ ] Define file schema version 1.
- [ ] Define `manifest.json` model.
- [ ] Define card JSON model.
- [ ] Define deck JSON model.
- [ ] Define review event JSONL model.
- [ ] Define backup folder structure.
- [ ] Define conflict folder structure.
- [ ] Add JSON encoding/decoding helpers.
- [ ] Add data folder creation logic.
- [ ] Add corrupted file detection and reporting.

## Phase 3: Local Only

- [ ] Implement `LocalFileDataStore`.
- [ ] Choose default local data path.
- [ ] Create required folders on first launch.
- [ ] Implement card create/update/delete.
- [ ] Implement deck create/update/delete.
- [ ] Implement review event append.
- [ ] Implement full snapshot load.
- [ ] Implement full snapshot write.
- [ ] Implement import.
- [ ] Implement export.
- [ ] Implement backup creation.
- [ ] Implement backup restore.
- [ ] Add Local Only storage tests.

## Phase 4: iCloud Drive Folder

- [ ] Implement `ICloudDriveFolderDataStore`.
- [ ] Add folder picker UI.
- [ ] Store selected folder in `StorageSettings`.
- [ ] Validate selected folder permissions.
- [ ] Detect whether selected folder appears to be inside iCloud Drive.
- [ ] Show explanatory copy when folder is not inside iCloud Drive.
- [ ] Scan folder on app startup.
- [ ] Rescan folder when app enters foreground.
- [ ] Add file change watching where practical.
- [ ] Detect newer on-disk card versions before write.
- [ ] Deduplicate review events by event id.
- [ ] Detect duplicate/conflict files.
- [ ] Move conflicted card versions into `conflicts/`.
- [ ] Add conflict count to settings UI.
- [ ] Add iCloud Drive Folder storage tests.

## Phase 5: CloudKit Hardening

- [ ] Confirm personal learning data uses CloudKit Private Database.
- [ ] Confirm no personal learning data is stored in Public Database.
- [ ] Map current CloudKit records to `Deck`, `Card`, `ReviewEvent`, and `UserSettings`.
- [ ] Add `updatedAt`, `deletedAt`, and `deviceId` where missing.
- [ ] Ensure review events are append-only records.
- [ ] Add iCloud account availability checks.
- [ ] Add CloudKit container availability checks.
- [ ] Add sync health reporting.
- [ ] Add transient error retry policy.
- [ ] Add offline behavior documentation.
- [ ] Add CloudKit storage tests where feasible.

## Phase 6: Mode Switching and Migration

- [ ] Implement snapshot export for `LocalFileDataStore`.
- [ ] Implement snapshot import for `LocalFileDataStore`.
- [ ] Implement snapshot export for `ICloudDriveFolderDataStore`.
- [ ] Implement snapshot import for `ICloudDriveFolderDataStore`.
- [ ] Implement snapshot export for `CloudKitDataStore`.
- [ ] Implement snapshot import for `CloudKitDataStore`.
- [ ] Add record count validation.
- [ ] Add checksum or equivalent integrity validation.
- [ ] Implement Local Only -> iCloud Drive Folder.
- [ ] Implement Local Only -> CloudKit.
- [ ] Implement iCloud Drive Folder -> Local Only.
- [ ] Implement iCloud Drive Folder -> CloudKit.
- [ ] Implement CloudKit -> Local Only.
- [ ] Implement CloudKit -> iCloud Drive Folder.
- [ ] Ensure source data is not deleted after migration.
- [ ] Ensure settings switch only after migration validation passes.
- [ ] Add rollback handling for failed migrations.
- [ ] Add migration tests.

## Phase 7: Settings UI

- [ ] Add "Data and Sync" settings screen.
- [ ] Show current storage mode.
- [ ] Show current data location.
- [ ] Show last sync/check time.
- [ ] Show health status.
- [ ] Add Local Only mode option.
- [ ] Add iCloud Drive Folder mode option.
- [ ] Add CloudKit mode option.
- [ ] Add Choose Folder action.
- [ ] Add Export Data action.
- [ ] Add Import Data action.
- [ ] Add Switch Storage Mode action.
- [ ] Add Check Sync Status action.
- [ ] Add Resolve Conflicts action.
- [ ] Add Create Backup action.
- [ ] Add Restore Backup action.
- [ ] Add privacy explanation copy for each mode.

## Phase 8: Conflict Resolution

- [ ] Define conflict model.
- [ ] Detect edit/edit conflict.
- [ ] Detect delete/edit conflict.
- [ ] Keep review event merge automatic by event id.
- [ ] Add conflict list UI.
- [ ] Add card comparison UI.
- [ ] Add keep local version action.
- [ ] Add keep incoming version action.
- [ ] Add duplicate as new card action.
- [ ] Add mark resolved action.
- [ ] Add conflict resolution tests.

## Phase 9: Documentation and Release Readiness

- [ ] Update user manual with storage mode explanations.
- [ ] Update developer documentation with storage architecture.
- [ ] Add privacy wording to settings UI.
- [ ] Add migration warnings and recovery instructions.
- [ ] Add troubleshooting section for iCloud Drive sync delays.
- [ ] Add troubleshooting section for CloudKit account issues.
- [ ] Add release checklist for storage migration.
- [ ] Run full regression test pass.

## Open Decisions

- [ ] Decide whether Local Only should be the default for new installs.
- [ ] Decide whether iCloud Drive Folder should be recommended during onboarding.
- [ ] Decide whether CloudKit should be hidden under advanced settings or shown equally.
- [ ] Decide exact storage path for sandboxed and non-sandboxed builds.
- [ ] Decide whether media files are included in Phase 1 file format.
- [ ] Decide how much offline queueing CloudKit mode should support.
- [ ] Decide whether migration should require an automatic backup before switching.
