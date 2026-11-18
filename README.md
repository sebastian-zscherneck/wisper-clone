# Wisper Clone

A macOS dictation app inspired by Wispr Flow. Hold a global hotkey, speak, release — your words are transcribed and pasted into whatever app you're using. By default everything runs on your Mac: Parakeet for speech, Apple's on-device language model for cleanup. No account, no backend, no telemetry. The OpenAI API with your own key remains available as a second engine.

## Quick start

You need an Apple Silicon Mac and the Swift toolchain (`xcode-select --install` is enough).

```sh
git clone https://github.com/sebastian-zscherneck/wisper-clone.git
cd wisper-clone
Scripts/package-app.sh --install --open
```

1. The app appears in the Dock. Click it to open the main window.
2. Open Settings → Privacy & Permissions and allow Microphone, Input Monitoring and Accessibility.
3. The first launch downloads the speech model (about 600 MB). Settings → Transcription & AI shows when it is ready.
4. Hold `Fn`, speak, release. Double-tap `Fn` for hands-free dictation.

For AI cleanup, turn on Apple Intelligence in System Settings (macOS 26 or newer). Without it, dictation still works and pastes the plain transcript.

## Features

- **Push-to-talk dictation**: hold a global shortcut to record, release to transcribe and paste. Double-tap for hands-free mode, Esc to cancel.
- **Custom hotkeys**: click a shortcut field in the settings and press any key combo, bare modifier chord (like Fn), or mouse side button to assign it — separate bindings for dictation and Command Mode.
- **Command Mode**: select text anywhere, hold the command hotkey, and speak an instruction ("make this more formal", "mach das kürzer") — the AI edits the selection in place.
- **AI cleanup levels**: from raw transcript to lightly polished text, with per-app tone (chat, email, docs) and one-shot undo of AI edits.
- **Bilingual dictation**: the default prompt is tuned for mixed German/English speech and preserves the spoken language instead of translating. Adjust it in `TranscriptionPromptBuilder.swift` for your own language mix.
- **Per-app signature**: automatically append a line like "Made with WisprFlow" to dictations in the apps you pick (Slack and WhatsApp are pre-filled), with a hotkey that flips the decision for the next dictation only — on where it would be off, off where it would be on.
- **Personal dictionary & rules**: teach the transcriber your names and technical terms, and set persistent rules ("never use exclamation marks") that apply to every cleanup and command.
- **Floating Flow Bar** with live waveform, transcript history, and microphone selection that doesn't touch your system default input (and avoids switching AirPods out of their high-quality playback profile). With the lid closed, the built-in microphone is skipped whenever another microphone is connected.
- **Guarded against accidents**: silent or accidental sub-second recordings are discarded quietly instead of hallucinated into text. Text that comes back in the wrong script is dropped, and a light cleanup that rewords what you said is replaced by your own words.
- **Dictionary correction without AI**: misheard names are rewritten to the spelling in your dictionary right after transcription ("Flobar" becomes "Flow Bar"). Terms need at least six letters.
- **Optional sound and haptic feedback**: short tones and a trackpad tap when a dictation starts, ends, is cancelled or fails. Both are off by default and can be turned on under Settings → System. The tones are synthesized in code. To use your own sounds, put `started.wav`, `finished.wav`, `cancelled.wav` or `failed.wav` into `~/Library/Application Support/WisperClone/Sounds` and restart the app. The tap is only felt while a finger rests on the trackpad.

## Processing engines

Pick the engine under Settings → Transcription & AI.

| Engine | Speech-to-text | AI cleanup and Command Mode | Needs |
|---|---|---|---|
| On this Mac (default) | Parakeet Ultra or Parakeet v3 via [FluidAudio](https://github.com/FluidInference/FluidAudio), about 600 MB, downloaded once. Dictionary words are boosted against the audio with Parakeet CTC (about 100 MB) | Apple's on-device language model, or fast rule-based cleanup without a language model | Apple Silicon. Cleanup and Command Mode need macOS 26 with Apple Intelligence turned on |
| OpenAI API | `gpt-4o-transcribe` / `gpt-4o-mini-transcribe` | `gpt-4o-mini`, `gpt-5.4-mini` | Your own API key |

The on-device language model is small. It uses its own short cleanup prompt (`CleanupPromptBuilder.localBasePrompt`) and no per-app tone. Parakeet detects the language itself, so the language setting only applies to OpenAI.

## Main window, menu bar and Dock

- **Main window** with a sidebar: Home (usage numbers, last transcript, history by day), Dictionary, AI Rules and Signature. Open it by clicking the Dock icon.
- **Settings** as a sheet over the main window (⌘,): General, System, Transcription & AI, Privacy & Permissions.
- **Flow Bar**: a small capsule at the bottom of the screen. It grows into a waveform while you dictate and shows cancel and confirm buttons in hands-free mode.
- **Dock icon**: on by default, can be turned off under Settings → System.
- **Menu bar icon**: off by default. Turn it on under Settings → System to start or stop a dictation, paste or copy the last transcript and switch microphone and cleanup level from the menu bar. It is always shown while the Dock icon is off.

## Requirements

- macOS 14 or newer (macOS 26 for on-device AI cleanup)
- Swift 6.3 or newer (full Xcode recommended; Command Line Tools are enough to build)
- Optional: an OpenAI API key for the OpenAI engine

## Your OpenAI API key (OpenAI engine only)

With the OpenAI engine selected, the app talks directly to the OpenAI API with **your own key** — you pay OpenAI for exactly what you use.

1. Create a key at [platform.openai.com/api-keys](https://platform.openai.com/api-keys) (requires an API account with billing set up — note that a ChatGPT Plus/Pro subscription does **not** include API usage; API billing is separate).
2. Launch the app, open Settings → Transcription & AI, choose "OpenAI API" and paste the key.
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

- **With the default on-device engine nothing leaves your Mac.** The only network access is the one-time download of the speech model.
- **With the OpenAI engine, sent to OpenAI (and nowhere else):** your audio recordings, and — depending on the feature you use — the selected text (Command Mode), the frontmost app name/window title (used to pick the right tone), your dictionary terms, and your AI rules.
- **Stored locally only:** transcript history, preferences, dictionary, and rules (UserDefaults); your API key (Keychain).
- **No telemetry, no analytics, no third-party services.**

Audio files are temporary and deleted after transcription. If you dictate confidential material with the OpenAI engine, review [OpenAI's API data usage policies](https://openai.com/policies/api-data-usage-policies) first.

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
