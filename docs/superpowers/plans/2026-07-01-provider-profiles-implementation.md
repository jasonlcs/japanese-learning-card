# Provider Profiles Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the single AI provider settings form with named provider profiles that preserve provider configuration, safely manage API keys, and show verification status.

**Architecture:** Add profile metadata to `AppSettings` while keeping `providerConfig` mirrored to the active profile for compatibility. Move profile mutation into view-model/core helpers and keep the Settings UI as a thin editor with local draft text for stable focus.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, XCTest, Keychain-backed `SecretStore`.

---

## File Structure

- Modify `Sources/JapaneseLearningCardCore/Models.swift`: add `ProviderProfile`, `ProviderVerificationStatus`, profile fields, decode migration helpers.
- Modify `Sources/JapaneseLearningCardCore/KeychainStore.swift`: add key existence check to `SecretStore`.
- Modify `Sources/JapaneseLearningCardUI/AppViewModel.swift`: add active-profile helpers, profile CRUD, validation, key clearing, and key status resolution.
- Modify `Sources/JapaneseLearningCardUI/RootView.swift`: replace AI provider settings with profile picker/card/editor.
- Add `Tests/JapaneseLearningCardCoreTests/ProviderProfileTests.swift`: migration and model behavior.
- Add `Tests/JapaneseLearningCardUITests/ProviderProfileViewModelTests.swift` if practical; otherwise keep view-model logic covered through core tests and full build.

## Tasks

### Task 1: Core Profile Model

**Files:**
- Modify `Sources/JapaneseLearningCardCore/Models.swift`
- Add `Tests/JapaneseLearningCardCoreTests/ProviderProfileTests.swift`

- [x] Add `ProviderVerificationStatus` and `ProviderProfile`.
- [x] Add `providerProfiles` and `activeProviderProfileId` to `AppSettings`.
- [x] Normalize decoded settings so old JSON creates one profile from `providerConfig`.
- [x] Mirror `providerConfig` from the active profile after decode.
- [x] Add tests for old-settings migration, invalid active profile fallback, and default profile creation.
- [x] Run `swift test --filter JapaneseLearningCardCoreTests.ProviderProfileTests`.

### Task 2: Secret Store Key Status

**Files:**
- Modify `Sources/JapaneseLearningCardCore/KeychainStore.swift`
- Use in `Sources/JapaneseLearningCardUI/AppViewModel.swift`

- [x] Add `hasAPIKey(reference:) throws -> Bool` to `SecretStore`.
- [x] Implement it in `KeychainStore` using Keychain metadata lookup without returning secret data.
- [x] Add default protocol implementation if needed for test fakes.
- [x] Run `swift build`.

### Task 3: ViewModel Profile Operations

**Files:**
- Modify `Sources/JapaneseLearningCardUI/AppViewModel.swift`

- [x] Add a `ProviderKeyStatus` display enum.
- [x] Add published key-status state for the active profile.
- [x] Implement active profile selection, create, duplicate, delete, config update, preset update, validation, and key clearing.
- [x] Ensure validation with empty input uses the stored key, and validation with new input saves only after success.
- [x] Keep `settings.providerConfig` mirrored to the active profile before LLM calls.
- [x] Run `swift build`.

### Task 4: Settings UI Profile Editor

**Files:**
- Modify `Sources/JapaneseLearningCardUI/RootView.swift`

- [x] Replace the AI settings box with active profile picker, status summary, profile action buttons, profile fields, API key replacement field, clear key, and verify.
- [x] Preserve local draft behavior for text fields and commit on submit/focus loss.
- [x] Remove or stop using global provider preset binding for the profile editor.
- [x] Run `swift build`.

### Task 5: Full Verification

**Files:**
- Review all modified files.

- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Inspect `git diff --stat` and `git status --short`.
- [x] Commit only source, tests, and plan changes; leave `.build-ios/` untracked.
