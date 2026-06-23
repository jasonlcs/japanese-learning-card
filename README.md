# Japanese Learning Card

A native macOS menu bar app for periodic Japanese vocabulary cards. It crawls configured URLs, asks an OpenAI-compatible provider to extract learning material, stores generated cards locally, and shows cards from a menu bar popover on a schedule.

## Run

```sh
swift run JapaneseLearningCard
```

The app uses `NSStatusItem` and sets the activation policy to accessory, so it appears in the menu bar instead of as a normal Dock app.

## Build App Bundle And DMG

```sh
chmod +x build-app.sh
./build-app.sh
```

Outputs:

- `.build/app/JapaneseLearningCard.app`
- `.build/app/JapaneseLearningCard.dmg`

By default the script uses ad-hoc signing for local development. For Developer ID signing:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./build-app.sh
```

GitHub Actions notarization runs on tags named `v*` when the repository has these secrets:

- `DEVELOPER_CERTIFICATE_BASE64`
- `CERTIFICATE_PASSWORD`
- `APPLE_ID`
- `APPLE_APP_PASSWORD`
- `APPLE_TEAM_ID`

## Verify

This environment does not expose `XCTest` or Swift `Testing`, so the package includes a small executable verification target:

```sh
swift build
swift run JapaneseLearningCardCoreChecks
```

## Data And Secrets

- App data is stored in SQLite at `~/Library/Mobile Documents/com~apple~CloudDocs/JapaneseLearningCard/store.sqlite` when iCloud Drive is available; otherwise it falls back to `~/Library/Application Support/JapaneseLearningCard/store.sqlite`.
- Crawled documents, generated learning cards, and AI-generated quiz questions are persisted in the database so they can be shared across Macs using the same iCloud-backed file.
- The app reloads from the backing database on each read so changes synced from another Mac are picked up as soon as iCloud Drive finishes syncing.
- API keys are stored in macOS Keychain under the configured keychain reference.
- The default provider base URL is `https://api.openai.com/v1`, but any OpenAI-compatible `chat/completions` endpoint can be configured.

## Current MVP Scope

- Menu bar popover with card, AI article, quiz, settings, and history views.
- Multi-URL source management.
- Background crawl and background card generation.
- AI-generated Japanese articles on a schedule (or on demand) at user-selected JLPT levels, with auto-extracted vocabulary cards.
- OpenAI-compatible provider abstraction.
- SQLite persistence plus Keychain for API keys.
- Simple card selection: fresh cards, then oldest reviewing cards, excluding skipped cards.
- AI-generated multiple-choice quiz questions with answer feedback and Traditional Chinese explanations.

## AI Article Generator

Beyond crawling user-configured URLs, the app can ask the LLM to write a short Japanese article at one or more JLPT levels (N1–N5 + Unknown), then run the same card-extraction pipeline against the generated text. Configurable in the **AI 文章** popover tab:

- Multi-select JLPT levels for each generated article.
- Optional custom theme (e.g. `旅行-京都`); leave blank to let the model pick.
- Manual `立即產生文章` button for instant generation.
- Optional periodic generation (1–168 hours) when `啟用週期產生` is on.
- The generated article is stored as a `CrawledDocument` plus a `GeneratedArticle` record, so dedup, history, and quiz flows work the same as web sources.
