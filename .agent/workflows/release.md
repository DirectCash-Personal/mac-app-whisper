---
description: How to release a new version of SuperWhisper
---

# SuperWhisper Release Workflow

## Prerequisites

- Xcode command line tools installed
- All code changes committed

## Steps

### 1. Make your code changes

Edit the code as needed for the new version.

// turbo

### 2. Run the release script

```bash
cd /Users/lucascanavarro/Desktop/Em\ Andamento/mac-app-whisper/SuperWhisper
./scripts/release.sh <VERSION>
```

Example: `./scripts/release.sh 1.1.0`

This script will:

- Update the version number in `project.yml` and `Info.plist`
- Build a Release version of the app
- Create a `.dmg` file
- Generate/update `appcast.xml`

### 3. Commit and push

```bash
cd /Users/lucascanavarro/Desktop/Em\ Andamento/mac-app-whisper
git add -A
git commit -m "release: v<VERSION>"
git tag v<VERSION>
git push origin main --tags
```

### 4. Create GitHub Release

1. Go to: https://github.com/DirectCash-Personal/mac-app-whisper/releases/new
2. Select the tag `v<VERSION>`
3. Title: `SuperWhisper v<VERSION>`
4. Upload the `.dmg` file from `SuperWhisper/build/SuperWhisper-<VERSION>.dmg`
5. Add release notes
6. Click **Publish release**

### 5. Done! 🎉

Users running the previous version will see an update notification within 24 hours (or immediately if they click "Check for Updates" in the app menu).
