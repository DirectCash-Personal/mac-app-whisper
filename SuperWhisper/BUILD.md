# BUILD.md — SuperWhisper

## Prerequisites

- **macOS 14.0 (Sonoma)** or later
- **Xcode 15.0** or later
- **Swift 5.9** or later
- **OpenAI API Key** ([get one here](https://platform.openai.com/api-keys))

## Quick Start

### 1. Open in Xcode

```bash
cd SuperWhisper
open SuperWhisper.xcodeproj
```

Or, if using Swift Package Manager:

```bash
cd SuperWhisper
swift build
```

### 2. Build & Run

1. Open the project in Xcode
2. Select **SuperWhisper** scheme
3. Select **My Mac** as the run destination
4. Press `Cmd+R` to build and run

### 3. First Launch Setup

1. **Grant Permissions** — The app will guide you through setting up Microphone and Accessibility permissions
2. **Enter API Key** — Go to Settings (Cmd+,) → General → Enter your OpenAI API key
3. **Configure Shortcut** — Default is `Cmd+D`, customize in Settings → Shortcuts

### 4. Usage

1. Press your shortcut (`Cmd+D` by default) to start recording
2. Speak normally
3. Press the shortcut again or click Stop to finish
4. The app transcribes your speech and pastes it into your current app

## Building for Distribution

### Create Archive

```bash
xcodebuild archive \
  -scheme SuperWhisper \
  -destination 'platform=macOS' \
  -archivePath build/SuperWhisper.xcarchive
```

### Export .app

```bash
xcodebuild -exportArchive \
  -archivePath build/SuperWhisper.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/
```

### Create DMG (optional)

```bash
hdiutil create -volname SuperWhisper \
  -srcfolder build/SuperWhisper.app \
  -ov -format UDZO \
  build/SuperWhisper.dmg
```

## Code Signing Notes

- For local development: Disable sandbox in Signing & Capabilities (required for Accessibility API)
- For distribution: Sign with Developer ID certificate
- Notarize: `xcrun notarytool submit build/SuperWhisper.dmg --apple-id YOUR_ID --team-id YOUR_TEAM`

## Running Tests

```bash
swift test
# or
xcodebuild test -scheme SuperWhisper -destination 'platform=macOS'
```

## Project Structure

```
SuperWhisper/
├── SuperWhisper/
│   ├── App/              # App entry point + delegate
│   ├── UI/               # Design tokens + reusable components
│   │   └── Components/   # GlassCard, buttons, inputs, waveform
│   ├── Features/
│   │   ├── Settings/     # Settings window (General, Shortcuts, About)
│   │   ├── DictationOverlay/  # Floating overlay panel
│   │   ├── Permissions/  # Permission onboarding
│   │   └── MainWindow/   # Main app window
│   ├── Domain/           # State machine, models
│   ├── Services/         # Audio, Transcription, Paste, Hotkey, Settings, Permissions
│   └── Resources/        # Assets
├── Tests/                # Unit tests
├── ARCHITECTURE.md       # Platform decision + architecture
├── PERMISSIONS.md        # Permission setup guide
├── BUILD.md              # This file
└── Package.swift         # SPM configuration
```
