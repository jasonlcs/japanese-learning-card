# Provider Profiles Design

## Goal

Make AI provider configuration easier and safer by replacing the single global provider settings form with named provider profiles. Users should always know which provider/profile is active, whether its API key exists, when it was last verified, and whether switching providers will preserve previous settings.

## Current Problem

The app currently stores one `ProviderConfig` in `AppSettings`:

- `preset`
- `baseURL`
- `model`
- `apiKeyKeychainRef`
- `structuredOutput`
- optional organization/project/headers

The API key itself is stored in Keychain under `apiKeyKeychainRef`. The settings UI lets users change preset, base URL, model, keychain reference, and API key independently. This is confusing because switching provider presets rewrites the current config and changes the keychain reference, but the UI does not clearly show whether a key exists for the new reference or whether the previous provider's config is still recoverable.

## Product Decision

Use full provider profiles with verification status.

Each profile owns a complete provider configuration plus status metadata. Switching profiles changes the active profile only; it must not overwrite other profiles.

## Data Model

Add:

```swift
public struct ProviderProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var config: ProviderConfig
    public var lastVerifiedAt: Date?
    public var lastVerificationStatus: ProviderVerificationStatus
    public var lastVerificationMessage: String?
    public var verifiedModelCount: Int?
    public var updatedAt: Date
}

public enum ProviderVerificationStatus: String, Codable, CaseIterable, Sendable {
    case unverified
    case success
    case failed
    case missingKey
}
```

Add to `AppSettings`:

```swift
public var providerProfiles: [ProviderProfile]
public var activeProviderProfileId: UUID?
```

Keep `providerConfig` for backward compatibility and as the resolved active config during migration. After profiles exist, `providerConfig` should mirror the active profile's `config` so existing code paths can continue reading `snapshot.settings.providerConfig` until they are gradually cleaned up.

## Migration

When decoding old settings with no profiles:

1. Create one profile from the existing `providerConfig`.
2. Name it from the preset display name, for example `OpenAI` or `Google AI Studio (Gemma)`.
3. Set `activeProviderProfileId` to the new profile id.
4. Set verification status to `unverified`.
5. Do not move or rewrite any Keychain item.

Because the profile uses the same `apiKeyKeychainRef`, any existing key remains available.

If settings contain profiles but no valid active id, select the first profile. If there are no profiles, create a default OpenAI profile.

## API Key Behavior

Security rule: the UI must not read back, reveal, or copy API keys from Keychain.

Allowed operations:

- Save/replace key: user pastes a new key into an empty secure field, then validates.
- Verify with existing key: if the secure field is empty, validation uses the existing Keychain key for the active profile.
- Clear key: delete the active profile's Keychain item and mark the profile as `missingKey`.
- Key status check: the app may query whether a Keychain item exists, but must not expose the stored value in UI state.
- Keychain reference edits: changing a profile's keychain reference changes which Keychain item the profile uses. It does not automatically copy or move the old secret.

Validation behavior:

- If the secure field contains a new key:
  - Use the new key for validation.
  - Save it to Keychain only after validation succeeds.
- If the secure field is empty:
  - Attempt validation with the existing Keychain key.
  - If no key exists, set status to `missingKey`.
- On success:
  - `lastVerificationStatus = .success`
  - `lastVerifiedAt = now`
  - `verifiedModelCount = model count`
  - `lastVerificationMessage = nil`
  - clear the secure field
- On failure:
  - `lastVerificationStatus = .failed`
  - `lastVerificationMessage = error.localizedDescription`
  - do not save a new key

## UI Design

In Settings > AI:

Top area:

- Active Profile picker
- Key status chip:
  - `Key saved`
  - `Missing key`
  - `Unverified`
  - `Verification failed`
- Last verified timestamp when available
- Model count when available

Profile actions:

- New Profile
- Duplicate Profile
- Delete Profile
- Clear API Key

Editing area:

- Profile name
- Provider preset
- Base URL
- Model
- JSON output mode
- Keychain reference
- API key secure field with placeholder `Paste new key to replace; leave blank to use saved key`
- Verify button

Interaction rules:

- Editing profile name/base URL/keychain reference should use draft state and commit on submit or focus loss, matching the recent settings focus fix.
- Switching active profile immediately updates the effective provider configuration.
- Changing provider preset inside a profile updates that profile's base URL, default model, structured output mode, and curated model list only for that profile.
- Deleting the active profile should switch to another profile. If it was the last profile, create a default profile instead of leaving the app without a provider config.

## Status Copy

Recommended user-facing labels:

- `Key saved` when Keychain contains an item for the profile reference.
- `Missing key` when Keychain has no item or the user cleared it.
- `Verified today 13:20` for recent successful validation.
- `Verification failed` with the error message shown below the profile card.
- `Not verified` for migrated or newly-created profiles.

Because Keychain lookup can throw, the status resolver should distinguish:

- missing item
- unreadable keychain error
- verification failure

The status resolver can use the existing `apiKey(reference:)` method internally, but it should reduce the result to status metadata immediately. The returned secret string must not be stored in `@Published`, `@State`, logs, profile metadata, or diagnostics.

## Compatibility With Existing Code

Existing LLM calls should continue using `settings.providerConfig` initially. `AppViewModel` should keep `settings.providerConfig` synchronized from the active profile whenever profile state changes.

Implementation should add helper methods instead of spreading profile mutation across the UI:

- `activeProviderProfile`
- `applyProviderProfile(_:)`
- `createProviderProfile(from:)`
- `duplicateProviderProfile(_:)`
- `deleteProviderProfile(_:)`
- `updateActiveProviderProfileConfig(_:)`
- `validateAndSaveActiveProviderProfile(apiKeyInput:)`
- `clearActiveProviderProfileKey()`

## Testing

Core tests:

- Old `AppSettings` JSON without profiles decodes into one profile.
- Active profile config mirrors `providerConfig`.
- Missing active profile id falls back to first profile.
- Deleting the last profile creates a default replacement.
- Validation status updates do not alter API key content in serialized settings.

Secret store tests with a fake `SecretStore`:

- Empty API key input validates with existing key.
- Empty API key input with no stored key marks `missingKey`.
- New key is saved only after validation succeeds.
- Clear key deletes only the active profile key reference.

UI/view-model tests or manual verification:

- Switching profiles preserves previous profile base URL/model/key reference.
- UI shows saved/missing key state.
- API key field is always empty after validation and after switching profiles.
- Provider preset change affects only the active profile.

## Out Of Scope

- Showing or copying stored API keys.
- Encrypting profile metadata; only API keys remain in Keychain.
- Syncing Keychain secrets through CloudKit or iCloud.
- Per-source provider selection.
- Cost tracking per profile.
