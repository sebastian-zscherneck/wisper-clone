# Wisper Clone

A macOS menu bar dictation app inspired by Wispr Flow. Hold a global hotkey, speak, release — your words are transcribed with OpenAI and pasted into whatever app you're using. Bring your own OpenAI API key; there is no account, no backend, and no telemetry.

## Features

- **Push-to-talk dictation**: hold a global shortcut to record, release to transcribe and paste. Double-tap for hands-free mode, Esc to cancel.
- **Custom hotkeys**: click a shortcut field in the settings and press any key combo, bare modifier chord (like Fn), or mouse side button to assign it — separate bindings for dictation and Command Mode.
- **Command Mode**: select text anywhere, hold the command hotkey, and speak an instruction ("make this more formal", "mach das kürzer") — the AI edits the selection in place.
- **AI cleanup levels**: from raw transcript to lightly polished text, with per-app tone (chat, email, docs) and one-shot undo of AI edits.
- **Bilingual dictation**: the default prompt is tuned for mixed German/English speech and preserves the spoken language instead of translating. Adjust it in `TranscriptionPromptBuilder.swift` for your own language mix.
- **Personal dictionary & rules**: teach the transcriber your names and technical terms, and set persistent rules ("never use exclamation marks") that apply to every cleanup and command.
- **Floating Flow Bar** with live waveform, transcript history, and microphone selection that doesn't touch your system default input (and avoids switching AirPods out of their high-quality playback profile).
- **Guarded against accidents**: silent or accidental sub-second recordings are discarded instead of hallucinated into text.

## Requirements

- macOS 14 or newer
- Swift 6.3 or newer (full Xcode recommended; Command Line Tools are enough to build)
- An OpenAI API key

## Your OpenAI API key

The app talks directly to the OpenAI API with **your own key** — you pay OpenAI for exactly what you use.

1. Create a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys) (requires an API account with billing set up — note that a ChatGPT Plus/Pro subscription does **not** include API usage; API billing is separate).
2. Launch the app, open the menu bar popover, and paste the key into the "OpenAI API key" field.
3. The key is stored in the **macOS Keychain** — never in a file, never in UserDefaults, and it is only ever sent to `api.openai.com`.

Typical dictation usage costs a few cents per day. You can set a hard spending limit in your OpenAI billing settings.

### Models used

| Task | Model | Defined in |
|---|---|---|
| Transcription (accurate) | `gpt-4o-transcribe` | `Core/DictationModels.swift` |
| Transcription (fast) | `gpt-4o-mini-transcribe` | `Core/DictationModels.swift` |
| Transcript cleanup | `gpt-4o-mini` | `Services/OpenAIChatClient.swift` |
| Command Mode | `gpt-5.4-mini` | `Services/OpenAIChatClient.swift` |

Change the constants in those files if you prefer different models.

## Privacy & data

- **Sent to OpenAI (and nowhere else):** your audio recordings, and — depending on the feature you use — the selected text (Command Mode), the frontmost app name/window title (used to pick the right tone), your dictionary terms, and your AI rules.
- **Stored locally only:** transcript history, preferences, dictionary, and rules (UserDefaults); your API key (Keychain).
- **No telemetry, no analytics, no third-party services.**

Audio files are temporary and deleted after transcription. If you dictate confidential material, review [OpenAI's API data usage policies](https://openai.com/policies/api-data-usage-policies) first.

## Build & run

Development run:

```sh
swift run WisperClone
```

For correct macOS permission behavior, build a local `.app` bundle instead:

```sh
chmod +x Scripts/package-app.sh
Scripts/package-app.sh --open
```

To install it into `~/Applications` and make it discoverable via Spotlight:

```sh
Scripts/package-app.sh --install --open
```

The packaging script creates and reuses a local self-signed code-signing identity (`Wisper Clone Local Code Signing`). Keeping that identity stable prevents macOS privacy permissions from drifting after each rebuild.

### macOS permissions

The app needs:

- **Microphone** — requested on first recording.
- **Accessibility** — for automatic paste and reading the selection in Command Mode.
- **Input Monitoring** — for the global hotkeys.

If shortcuts or paste stop working after a rebuild (stale TCC entries), reset and re-approve:

```sh
Scripts/reset-permissions.sh
open "$HOME/Applications/Wisper Clone.app"
```

## Tests

```sh
swift test
```

On machines with only Command Line Tools (no full Xcode), use the bundled runner instead:

```sh
Scripts/run-tests.sh
```

## License

[MIT](LICENSE). Not affiliated with OpenAI or Wispr.
