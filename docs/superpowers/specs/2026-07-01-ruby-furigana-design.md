# Ruby / Furigana Card Rendering Design

## Goal

Add full ruby / furigana support so Japanese kanji can display hiragana above the base text in both headwords and example sentences. Because the app is still in validation, existing cards should be migrated once with AI assistance, then the migration should never run again after it completes.

## Scope

In scope:

- Store structured ruby data for card headwords and Japanese example sentences.
- Ask AI card generation to return ruby segments for new cards.
- Run one automatic migration for existing cards when AI is configured.
- Render ruby segments in SwiftUI with fallback to existing plain text fields.
- Validate generated ruby enough to avoid corrupting cards.

Out of scope:

- A permanent user-facing "rebuild ruby" button.
- A long-term background job for repeated ruby maintenance.
- Perfect linguistic validation beyond ensuring the ruby structure maps back to the base text.
- Removing the existing `word`, `reading`, `exampleJa`, or `exampleReading` fields.

## Data Model

Add a small structured type in the core model:

```swift
public struct RubySegment: Codable, Equatable, Sendable {
    public var base: String
    public var ruby: String
}
```

Add optional ruby arrays to `LearningCard`:

```swift
public var wordRuby: [RubySegment]
public var exampleRuby: [RubySegment]
```

For backward compatibility, decoding should default missing arrays to `[]`. Existing fields remain the source of truth for search, matching, copy behavior, and fallback rendering:

- `word`
- `reading`
- `exampleJa`
- `exampleReading`

The structured ruby arrays are display metadata. A ruby array is considered usable only when concatenating all `base` values exactly equals the corresponding plain text field after the same whitespace normalization used by the app.

## AI Schema

Update card-generation prompts and decoding to accept:

```json
{
  "cards": [
    {
      "word": "勉強",
      "reading": "べんきょう",
      "wordRuby": [
        { "base": "勉強", "ruby": "べんきょう" }
      ],
      "exampleJa": "毎日、日本語を勉強します。",
      "exampleReading": "まいにち、にほんごをべんきょうします。",
      "exampleRuby": [
        { "base": "毎日", "ruby": "まいにち" },
        { "base": "、", "ruby": "" },
        { "base": "日本語", "ruby": "にほんご" },
        { "base": "を", "ruby": "" },
        { "base": "勉強", "ruby": "べんきょう" },
        { "base": "します。", "ruby": "" }
      ]
    }
  ]
}
```

Prompt rules:

- `wordRuby` and `exampleRuby` are required for new AI output.
- Each segment must preserve the original base text order.
- Kana-only particles, punctuation, and kana suffixes may use an empty `ruby`.
- Kanji-containing segments should have hiragana `ruby`.
- `base` segments must concatenate back to `word` or `exampleJa`.
- `reading` and `exampleReading` remain required as plain-text fallback.

Decoder behavior:

- If AI omits ruby arrays, decode the card and leave arrays empty.
- If ruby arrays fail validation, discard only the invalid ruby arrays and keep the card.
- Do not reject an entire card solely because ruby metadata is invalid.

## One-Time Migration

Add a migration marker to app settings or persisted app state. Preferred shape:

```swift
public var completedMigrations: [String]
```

Use migration id:

```text
ruby-v1
```

Startup behavior:

1. After the app loads its snapshot and provider settings, check whether `completedMigrations` contains `ruby-v1`.
2. If the marker exists, do nothing.
3. If the marker is missing, check whether there are existing cards missing usable `wordRuby` or `exampleRuby`.
4. If no cards need ruby, write the marker and stop.
5. If cards need ruby and AI configuration appears usable, run the migration once.
6. If AI configuration is missing or unusable, leave the marker unset and skip migration for this run.
7. If migration succeeds for all processable cards, write `ruby-v1` to `completedMigrations`.
8. If migration fails globally, leave the marker unset so the next app run can retry.

Partial failures:

- The migration should process cards in batches to limit prompt size and token usage.
- If a card fails validation, keep the original card unchanged and record the failure in logs/status.
- The migration can still complete if individual cards fail because of bad model output, but only when every card was attempted. This avoids repeatedly spending AI calls on the same validation-stage dataset.

This migration is not a permanent product feature. It should have minimal UI: a status message is enough while it runs. No settings button is required.

## Migration AI Request

Add a provider method such as:

```swift
func generateRuby(for cards: [LearningCard], settings: AppSettings) async throws -> [RubyBackfillResult]
```

Input should include each card id plus:

- `word`
- `reading`
- `exampleJa`
- `exampleReading`

Output should include each id plus `wordRuby` and `exampleRuby`. The decoder should match results by card id, validate each result, then update only the ruby arrays and `updatedAt`.

## UI Rendering

Create a SwiftUI `RubyText` component that accepts:

- `[RubySegment]`
- fallback plain text
- base font
- ruby font
- color options
- maximum line count when the parent needs clipping

Rendering approach:

- Render each segment as a small vertical stack: ruby text above base text.
- Segments with empty `ruby` render with reserved ruby height so line rhythm stays stable.
- Use a wrapping layout so long example sentences can wrap across lines.
- Keep copy buttons copying the plain sentence/headword, not the ruby display fragments.

Use `RubyText` in:

- `StyledLearningCard.wordHero`
- `StyledLearningCard.examplePanel`
- history / related-card rows only if space allows; otherwise keep the existing compact `Text(card.word)` plus `Text(card.reading)` presentation.

Fallback behavior:

- If `wordRuby` is invalid or empty, use existing `word` plus `reading` layout.
- If `exampleRuby` is invalid or empty, use existing `exampleJa` plus `exampleReading` layout.
- UI must remain readable before, during, and after migration.

## Storage and Sync

Because `LearningCard` is already stored as JSON inside SQLite rows and synced as payload data, adding Codable fields should be backward compatible:

- Old local records decode with empty ruby arrays.
- New records sync with ruby arrays included in their JSON.
- Conflict merging should treat ruby fields like other card content fields.
- Shallow-diff logic should be reviewed so ruby-only updates from migration do not accidentally mask unrelated conflicts.

## Error Handling

- Missing AI key: skip migration, leave marker unset, show a concise status message.
- AI request failure: stop migration, leave marker unset.
- Invalid result for one card: keep that card unchanged, record the card id in the migration outcome.
- Invalid result for an entire batch: keep the batch unchanged and continue with later batches only if the failure is a decode/validation issue. Stop on provider/network/auth errors.
- App restart during migration: marker remains unset, so the next startup retries.

## Testing

Core tests:

- Decode old `LearningCard` JSON without ruby fields.
- Decode new `LearningCard` JSON with ruby fields.
- Validate that ruby `base` segments concatenate to `word` / `exampleJa`.
- Reject invalid ruby metadata without rejecting the entire card payload.
- Ensure `ruby-v1` marker prevents repeated migration.

UI tests or previews:

- Headword with kanji and ruby.
- Kana-only word with no ruby.
- Mixed example sentence with kanji, kana, particles, and punctuation.
- Long example sentence wrapping across lines.
- Fallback rendering when ruby arrays are empty.

Manual verification:

- Start with an old store containing cards without ruby.
- Configure AI.
- Launch app and observe one migration pass.
- Restart app and verify migration does not run again.
- Generate a new card and verify it already includes ruby arrays.

## Open Decisions Resolved

- Existing cards should be migrated automatically once.
- The migration should not become a permanent user-facing feature.
- A completion marker should prevent future repeated AI spending.
- New AI-generated cards should include ruby arrays from the start.
