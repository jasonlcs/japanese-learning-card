# Ruby Furigana Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add structured ruby / furigana support for AI-generated cards and migrate existing cards once when AI is configured.

**Architecture:** Keep existing plain card fields as compatibility fallbacks, add structured ruby metadata for display, and validate ruby by reconstructing the original base text. Add a one-time app migration keyed by `ruby-v1`; new AI generation includes ruby arrays from the start.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI, XCTest, existing OpenAI-compatible chat client.

---

## File Structure

- Modify `Package.swift`: add test targets.
- Modify `Sources/JapaneseLearningCardCore/Models.swift`: add `RubySegment`, ruby fields, settings migration marker.
- Create `Sources/JapaneseLearningCardCore/RubySupport.swift`: ruby validation and fallback helpers.
- Modify `Sources/JapaneseLearningCardCore/LLMClient.swift`: prompt schema, decode ruby arrays, ruby backfill request.
- Modify `Sources/JapaneseLearningCardCore/LearningPipeline.swift`: one-time ruby backfill orchestration.
- Modify `Sources/JapaneseLearningCardUI/AppViewModel.swift`: trigger one-time migration after load when AI is configured.
- Create `Sources/JapaneseLearningCardUI/RubyText.swift`: SwiftUI ruby rendering component.
- Modify `Sources/JapaneseLearningCardUI/RootView.swift`: use ruby display in card hero and examples.
- Create `Tests/JapaneseLearningCardCoreTests/RubySupportTests.swift`: core model and validation tests.
- Create `Tests/JapaneseLearningCardCoreTests/LLMClientRubyTests.swift`: decode tests for ruby payloads.

## Tasks

### Task 1: Test Targets and Core Ruby Model

**Files:**
- Modify: `Package.swift`
- Modify: `Sources/JapaneseLearningCardCore/Models.swift`
- Create: `Sources/JapaneseLearningCardCore/RubySupport.swift`
- Create: `Tests/JapaneseLearningCardCoreTests/RubySupportTests.swift`

- [ ] Add SwiftPM test targets:

```swift
.testTarget(
    name: "JapaneseLearningCardCoreTests",
    dependencies: ["JapaneseLearningCardCore"]
),
.testTarget(
    name: "JapaneseLearningCardUITests",
    dependencies: ["JapaneseLearningCardUI"]
)
```

- [ ] Add `RubySegment` and default-decoding ruby arrays:

```swift
public struct RubySegment: Codable, Equatable, Sendable {
    public var base: String
    public var ruby: String
}
```

- [ ] Add validation helpers:

```swift
public enum RubySupport {
    public static func isUsable(_ segments: [RubySegment], for text: String) -> Bool {
        !segments.isEmpty && normalized(segments.map(\.base).joined()) == normalized(text)
    }
}
```

- [ ] Add tests proving old JSON decodes, valid ruby is usable, and invalid ruby is rejected.

- [ ] Run: `swift test --filter JapaneseLearningCardCoreTests.RubySupportTests`

### Task 2: AI Ruby Schema and Decode

**Files:**
- Modify: `Sources/JapaneseLearningCardCore/LLMClient.swift`
- Create: `Tests/JapaneseLearningCardCoreTests/LLMClientRubyTests.swift`

- [ ] Extend `CardPayload.Card` with optional `wordRuby` and `exampleRuby`.
- [ ] Update prompt JSON schema and rules so new generation requests structured ruby arrays.
- [ ] In `decodeCards`, keep the card when ruby metadata is absent or invalid, but only assign validated ruby arrays.
- [ ] Add tests for valid ruby decode and invalid ruby fallback.
- [ ] Run: `swift test --filter JapaneseLearningCardCoreTests.LLMClientRubyTests`

### Task 3: One-Time Ruby Migration

**Files:**
- Modify: `Sources/JapaneseLearningCardCore/Models.swift`
- Modify: `Sources/JapaneseLearningCardCore/LLMClient.swift`
- Modify: `Sources/JapaneseLearningCardCore/LearningPipeline.swift`
- Modify: `Sources/JapaneseLearningCardUI/AppViewModel.swift`
- Test: `Tests/JapaneseLearningCardCoreTests/RubySupportTests.swift`

- [ ] Add `completedMigrations: [String]` to `AppSettings`, defaulting to `[]`.
- [ ] Add migration id `ruby-v1`.
- [ ] Add `generateRuby(for:settings:)` to the provider protocol and concrete client.
- [ ] Implement pipeline backfill: select cards missing usable ruby, call AI in small batches, update ruby arrays, mark migration complete when attempted.
- [ ] Trigger migration once after snapshot load when provider config has an API key reference.
- [ ] Add tests for marker behavior and "needs ruby" selection.
- [ ] Run: `swift test --filter JapaneseLearningCardCoreTests`

### Task 4: SwiftUI Ruby Rendering

**Files:**
- Create: `Sources/JapaneseLearningCardUI/RubyText.swift`
- Modify: `Sources/JapaneseLearningCardUI/RootView.swift`

- [ ] Create `RubyText`, rendering each segment as ruby-over-base and wrapping across rows.
- [ ] Replace `wordHero` reading/headword display with ruby when usable.
- [ ] Replace example Japanese + reading rows with ruby when usable.
- [ ] Keep old display fallback when ruby arrays are empty or invalid.
- [ ] Run: `swift build`

### Task 5: Verification

**Files:**
- Review modified source files and tests.

- [ ] Run: `swift test`
- [ ] Run: `swift build`
- [ ] Inspect `git diff` for unrelated changes; do not stage pre-existing unrelated work.
- [ ] Report any verification failures with exact command and error summary.
