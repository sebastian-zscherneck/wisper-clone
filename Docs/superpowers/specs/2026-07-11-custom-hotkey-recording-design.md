# Custom Hotkey Recording — Design

Date: 2026-07-11 · Status: approved

## Goal

Users set their own dictation and Command Mode hotkeys by clicking a shortcut field and pressing the desired key/combo, instead of choosing from six hardcoded presets.

## Decisions

- Recorder-only UI: the preset toggles/pickers are removed. Defaults stay Fn + Mouse 5 (dictation), off (command).
- Multiple dictation bindings (add/remove list, minimum one). One optional command binding.
- Allowed gestures: modifier-only (Fn, ⌃, combos), key + modifiers, mouse side buttons ± modifiers. Plain character/space keys without modifiers are rejected (would hijack typing). Esc cancels recording.
- The `Hotkey` enum is fully replaced by a data-driven `HotkeyBinding` (approach A). No dual code paths.

## Model

`HotkeyBinding: Codable, Hashable, Sendable`

- `trigger`: `.key(code: UInt16)` | `.mouseButton(number: Int)` | `.modifiersOnly`
- `modifiers`: OptionSet — fn, control, option, shift, command
- `displayName`: symbols (⌃⌥⇧⌘, Fn, key name, "Mouse N")

## Matching (HotkeyManager)

- Both event paths (CGEventTap callback and NSEvent fallback) normalize into one shared matching routine — removes today's duplicated per-case handlers.
- Press: keyDown/mouseDown with the binding's exact modifier set held; modifiers-only bindings press when all their modifiers are held.
- Release: keyUp/mouseUp of the trigger regardless of current modifiers (no stuck state); modifiers-only releases when any required modifier drops.
- Overlapping modifier-only bindings (e.g. Fn vs Fn+⌃): the most specific match wins — generalizes the previous fnControl special case. Command binding is evaluated before dictation bindings, preserving current role precedence.
- Unchanged: gesture classifier (hold/double-tap), Esc cancel, ⌘⌃V paste-last.

## Recorder

- Clicking a hotkey field puts HotkeyManager into capture mode (same event stream).
- Key or mouse button + currently held modifiers → committed immediately on down.
- Modifier-only gesture → committed when the modifiers are released.
- Rejected: character/digit/space without modifiers. Esc cancels.
- Existing rule kept: the same binding cannot serve both roles; the last dictation binding cannot be removed or taken by the command role.

## Persistence & migration

- `AppPreferences.dictationBindings: [HotkeyBinding]` and `commandBinding: HotkeyBinding?`, JSON-encoded in UserDefaults under new keys.
- On load, legacy `preferences.hotkeys` / `preferences.commandHotkey` string values map 1:1 to equivalent bindings (fn → modifiers-only Fn, mouse5 → mouse button 4, optionSpace → key 49 + ⌥, …); saved back in the new format. No user loses their setup.

## Testing

- HotkeyManager tests keep driving the internal `handle(typeRawValue:flagsRawValue:keyCode:mouseButtonNumber:)` path, rewritten for bindings: matching matrix (key, mouse, modifier-only, specificity, cross-role precedence).
- Recorder rules: immediate commit, modifier-release commit, rejection, Esc cancel.
- Preferences migration tests (legacy keys → bindings, new-format round trip).
