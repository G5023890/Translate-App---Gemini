# TranslateGemini (macOS)

Menu bar app for translating selected text from English/Hebrew to Russian using Gemini API (`gemini-2.5-flash`).

## Features

- Global hotkey: `Shift+Command+L`
- Translation from selected text
- Fallback translation from clipboard
- API key in app settings (stored in Keychain)
- Launch at login toggle

## Requirements

- macOS 13+
- Xcode Command Line Tools (`swift` available in terminal)
- Valid Gemini API key

## Build

```bash
cd "/Users/grigorymordokhovich/Documents/Develop/Translate App - Gemini"
./scripts/build_app.sh
```

App output:

`/Users/grigorymordokhovich/Documents/Develop/Translate App - Gemini/dist/TranslateGemini.app`

## First Run Setup

1. Open the app from `dist/TranslateGemini.app`.
2. Open `⇢Я` menu -> `Настройки...`.
3. Paste Gemini API key and save.
4. In macOS Privacy settings, allow:
   - `Accessibility`
   - `Input Monitoring`

Without these permissions, selected-text capture will fail in many apps.

## Usage

1. Select text in any app.
2. Press `Shift+Command+L`.
3. If selection capture is blocked by the target app, use menu action `Перевести буфер` after `Command+C`.

## Repository

GitHub: [https://github.com/G5023890/Translate-App---Gemini](https://github.com/G5023890/Translate-App---Gemini)

## Security

See:

`/Users/grigorymordokhovich/Documents/Develop/Translate App - Gemini/Secrets.md`

Install local pre-commit secret scanning:

```bash
cd "/Users/grigorymordokhovich/Documents/Develop/Translate App - Gemini"
./scripts/install_git_hooks.sh
```
