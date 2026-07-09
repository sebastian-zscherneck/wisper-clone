# Wisper Clone

A personal macOS menu bar dictation app inspired by Whisper Flow.

## Current v1 behavior

- Hold a global shortcut to record.
- Release to transcribe with OpenAI `gpt-4o-transcribe`.
- Select the microphone used by the app without changing the system default input.
- Prefer non-Bluetooth microphones automatically so AirPods music stays in the high-quality playback profile.
- Use a German/English mixed dictation prompt by default, with optional German-only or English-only language hints.
- Lightly clean the transcript.
- Paste into the active app, or copy and notify if automatic paste cannot run.
- Keep temporary session history until the app quits.
- Store the OpenAI API key in macOS Keychain.

## Requirements

- macOS 14 or newer.
- Swift 6.3 or newer.
- Full Xcode is recommended for a polished signed app workflow. The Swift package can build with Command Line Tools.
- OpenAI API key.

## Run in development

```sh
swift run WisperClone
```

For the best permissions behavior, build a local `.app` bundle:

```sh
chmod +x Scripts/package-app.sh
Scripts/package-app.sh --open
```

The app will ask for microphone access when recording. Automatic paste requires enabling Accessibility access for the app in macOS Settings.

## Install for Spotlight

To make the app discoverable from Spotlight, install it into your user Applications folder:

```sh
Scripts/package-app.sh --install --open
```

This copies the signed bundle to `~/Applications/Wisper Clone.app` and registers it with LaunchServices. After that, you can launch it from Spotlight by searching for `Wisper Clone`.

The packaging script creates and reuses a local code-signing identity named `Wisper Clone Local Code Signing`. Keeping that identity stable prevents macOS privacy permissions from drifting after each rebuild.

## Reset macOS permissions

During development the app is ad-hoc signed locally. After rebuilding or reinstalling, macOS can keep stale privacy toggles that look enabled but no longer match the new local build. If global shortcuts or paste stop working after a rebuild, reset and approve the permissions again:

```sh
Scripts/reset-permissions.sh
open "$HOME/Applications/Wisper Clone.app"
```

Then allow the app again in Privacy & Security for Input Monitoring and Accessibility.

## Test

```sh
swift test
```
