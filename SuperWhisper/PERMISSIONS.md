# PERMISSIONS.md — SuperWhisper

SuperWhisper requires specific macOS permissions to function. This document explains what each permission does and how to enable them.

## Required Permissions

### 1. Microphone Access

**Why:** SuperWhisper captures your voice through the microphone to transcribe it into text using AI.

**How to enable:**

1. The app will automatically request permission on first use
2. Click **Allow** when the macOS permission dialog appears
3. If you previously denied it, go to:
   - **System Settings → Privacy & Security → Microphone**
   - Find **SuperWhisper** in the list and toggle it **ON**

**What the app does with mic data:**

- Records audio only while you hold/toggle the recording shortcut
- Audio is sent to OpenAI's servers for transcription
- Temporary audio files are deleted immediately after transcription

---

### 2. Accessibility Access

**Why:** SuperWhisper uses Accessibility APIs to simulate a Cmd+V paste into your currently focused application.

**How to enable:**

1. The app will prompt you to grant Accessibility access on first use
2. You'll be directed to:
   - **System Settings → Privacy & Security → Accessibility**
   - Click the **+** button
   - Navigate to SuperWhisper.app and add it
   - Toggle it **ON**

**What the app does with this permission:**

- Only simulates Cmd+V (paste) after a successful transcription
- This allows the transcribed text to be pasted directly into whatever app you're using
- No other keyboard events are simulated or monitored

---

## Optional Permissions

### 3. Input Monitoring (may be required)

**Why:** Some macOS versions require Input Monitoring for global keyboard shortcut capture.

**How to enable:**

1. Go to: **System Settings → Privacy & Security → Input Monitoring**
2. Click **+**, add SuperWhisper, toggle **ON**

**When is this needed?**

- If your global shortcut doesn't work after granting Accessibility
- macOS Sonoma+ may require this for `NSEvent.addGlobalMonitorForEvents`

---

## Troubleshooting

| Problem                          | Solution                                                           |
| -------------------------------- | ------------------------------------------------------------------ |
| Shortcut doesn't work            | Check Accessibility + Input Monitoring permissions                 |
| "Microphone not available"       | Check System Settings → Microphone                                 |
| Text doesn't paste               | Verify Accessibility permission is ON                              |
| Permission dialog doesn't appear | Reset permissions: `tccutil reset Microphone com.superwhisper.app` |

## Privacy Note

SuperWhisper does **not** store or log any audio data beyond the temporary file needed for transcription. Audio is sent directly to OpenAI's API over HTTPS and deleted immediately after the response is received.
