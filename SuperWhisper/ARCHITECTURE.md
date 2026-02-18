# ARCHITECTURE.md — SuperWhisper

## Platform Decision

**Choice: A) Native macOS (Swift/SwiftUI + AppKit)**

### Why Native macOS Wins

| Requirement       | Native macOS                             | Electron                        | Tauri                | Catalyst          | Flutter          |
| ----------------- | ---------------------------------------- | ------------------------------- | -------------------- | ----------------- | ---------------- |
| Global hotkey     | ✅ Carbon API / NSEvent — first-class    | ⚠️ Needs native module          | ⚠️ Rust binding      | ❌ No API         | ⚠️ Plugin needed |
| Floating overlay  | ✅ NSPanel — native, non-activating      | ⚠️ BrowserWindow hacks          | ⚠️ Platform-specific | ❌ No NSPanel     | ❌ No NSPanel    |
| Glass/vibrancy    | ✅ NSVisualEffectView — pixel-perfect    | ❌ CSS backdrop-filter ≠ native | ❌ Same issue        | ⚠️ Limited        | ❌ Not available |
| Low-latency audio | ✅ AVAudioEngine — native, zero overhead | ⚠️ Node native addon            | ✅ Rust cpal         | ⚠️ Same APIs      | ⚠️ Plugin needed |
| Paste injection   | ✅ CGEvent — direct system access        | ⚠️ Needs native module          | ⚠️ Rust binding      | ❌ Sandboxed      | ❌ Not available |
| Permissions UX    | ✅ Native dialogs, deep links            | ⚠️ Electron opens system prefs  | ⚠️ Manual            | ❌ Sandbox limits | ⚠️ Manual        |
| App size          | ✅ ~5MB                                  | ❌ ~150MB+ (Chromium)           | ✅ ~10MB             | ✅ ~8MB           | ⚠️ ~30MB         |
| Memory usage      | ✅ ~20MB                                 | ❌ ~200MB+                      | ✅ ~30MB             | ✅ ~25MB          | ⚠️ ~50MB         |

**Conclusion:** Native macOS is the clear winner for SuperWhisper. The app requires deep system integration (global hotkeys, overlay panels, accessibility APIs, audio capture) that all other options would need to work around.

---

## Architecture Layers

```
┌─────────────────────────────────────────┐
│              UI Layer (SwiftUI)         │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ Settings │ │ Overlay  │ │ Perms   │ │
│  │  Window  │ │  Panel   │ │ Screen  │ │
│  └────┬─────┘ └────┬─────┘ └────┬────┘ │
├───────┼─────────────┼────────────┼──────┤
│       │    Domain Layer          │      │
│  ┌────┴─────────────┴────────────┴────┐ │
│  │       AppStateManager              │ │
│  │  (idle→recording→processing→       │ │
│  │   success→idle)                    │ │
│  └──────────────┬─────────────────────┘ │
├─────────────────┼───────────────────────┤
│           Services Layer                │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ Audio    │ │Transcrip.│ │ Paste   │ │
│  │ Capture  │ │ Service  │ │ Service │ │
│  └──────────┘ └──────────┘ └─────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌─────────┐ │
│  │ Hotkey   │ │ Settings │ │ Perms   │ │
│  │ Service  │ │ Service  │ │ Service │ │
│  └──────────┘ └──────────┘ └─────────┘ │
└─────────────────────────────────────────┘
```

## Data Flow

1. **User presses global hotkey** → `HotkeyService` → `AppDelegate`
2. `AppDelegate` transitions `AppStateManager` to `.recording`
3. `OverlayPanel.showOverlay()` — floating panel fades in
4. `AudioCaptureService.startRecording()` — captures mic + computes waveform
5. **User presses hotkey again or Stop** → stop recording
6. `AppStateManager` → `.processing` — overlay shows spinner
7. `TranscriptionService.transcribe()` — uploads audio to OpenAI API
8. Response parsed → `PasteService.pasteText()` — copies to pasteboard + simulates Cmd+V
9. `AppStateManager` → `.success` — overlay shows "Text pasted ✓"
10. After 1.5s → overlay fades out → `.idle`

## Key Technology Choices

- **AVAudioEngine** for real-time mic capture (low-latency, stable start/stop)
- **WAV format** for recorded audio (reliable, widely supported by OpenAI)
- **Carbon `RegisterEventHotKey`** for true global hotkey (works even when app is not focused)
- **`NSPanel` with `NSVisualEffectView`** for native glass overlay
- **`CGEvent` Cmd+V simulation** for paste injection (requires Accessibility permission)
- **Keychain** for secure API key storage
- **UserDefaults** for all other preferences
