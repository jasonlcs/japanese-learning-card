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

- App data is stored in SQLite at `~/Library/Application Support/JapaneseLearningCard/store.sqlite`.
- Crawled documents, generated learning cards, and AI-generated quiz questions are persisted in the database.
- API keys are stored in macOS Keychain under the configured keychain reference.
- The default provider base URL is `https://api.openai.com/v1`, but any OpenAI-compatible `chat/completions` endpoint can be configured.

## Current MVP Scope

- Menu bar popover with card, quiz, settings, and history views.
- Multi-URL source management.
- Background crawl and background card generation.
- OpenAI-compatible provider abstraction.
- SQLite persistence plus Keychain for API keys.
- Simple card selection: fresh cards, then oldest reviewing cards, excluding skipped cards.
- AI-generated multiple-choice quiz questions with answer feedback and Traditional Chinese explanations.
