import Carbon.HIToolbox
import AppKit

/// Global pointer used by the Carbon event handler callback to invoke our Swift closure.
private var hotkeyServiceInstance: HotkeyService?

/// Carbon event handler callback — called system-wide whenever a registered hotkey is pressed.
private func carbonHotkeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    DispatchQueue.main.async {
        hotkeyServiceInstance?.onHotkeyPressed?()
    }
    return noErr
}

/// Service for registering and managing global keyboard shortcuts.
///
/// Supports two independent hotkeys:
/// 1. **F5 dictation key** — Always-on when "Force F5" toggle is enabled.
///    Remaps the macOS dictation key via hidutil at the HID driver level.
/// 2. **Custom shortcut** — User-configurable via Settings (default: ⌃D).
class HotkeyService {
    private let settingsService: SettingsService

    // Carbon event handler (shared by both hotkeys)
    private var eventHandlerRef: EventHandlerRef?

    // F5 dedicated hotkey (id: 1)
    private var f5HotkeyRef: EventHotKeyRef?

    // Custom user hotkey (id: 2)
    private var customHotkeyRef: EventHotKeyRef?

    /// Called when any registered hotkey is pressed.
    var onHotkeyPressed: (() -> Void)?

    init(settingsService: SettingsService) {
        self.settingsService = settingsService
    }

    deinit {
        unregister()
        hotkeyServiceInstance = nil
    }

    /// Register both global hotkeys (F5 + custom).
    func register() {
        unregister()

        // Store reference so the C callback can reach us
        hotkeyServiceInstance = self

        // 1. Install the single shared Carbon event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                       eventKind: UInt32(kEventHotKeyPressed))

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            carbonHotkeyHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("❌ Failed to install Carbon event handler: \(status)")
            return
        }

        // 2. Register F5 hotkey if Force F5 is enabled
        if settingsService.forceF5DictationKey {
            let f5ID = EventHotKeyID(signature: fourCharCode("SWF5"), id: 1)
            let f5Status = RegisterEventHotKey(
                96,     // F5 keyCode
                0,      // No modifiers
                f5ID,
                GetApplicationEventTarget(),
                0,
                &f5HotkeyRef
            )
            if f5Status == noErr {
                print("✅ F5 hotkey registered (Force F5 enabled)")
            } else {
                print("❌ Failed to register F5 hotkey: \(f5Status)")
            }
        }

        // 3. Register the custom user hotkey (if enabled)
        if settingsService.customShortcutEnabled {
            let keyCode = settingsService.hotkeyKeyCode
            let modifiers = settingsService.hotkeyModifiers

            // Skip if the custom hotkey IS F5 with no modifiers (already handled above)
            let isF5 = keyCode == 96 && modifiers == 0
            if !isF5 {
                print("🎹 Registering custom hotkey: keyCode=\(keyCode), modifiers=\(modifiers)")
                let customID = EventHotKeyID(signature: fourCharCode("SWCU"), id: 2)
                let carbonMods = carbonModifierFlags(from: modifiers)

                let customStatus = RegisterEventHotKey(
                    keyCode,
                    carbonMods,
                    customID,
                    GetApplicationEventTarget(),
                    0,
                    &customHotkeyRef
                )
                if customStatus == noErr {
                    print("✅ Custom hotkey registered")
                } else {
                    print("❌ Failed to register custom hotkey: \(customStatus)")
                }
            }
        } else {
            print("⏭️ Custom shortcut disabled, skipping registration")
        }
    }

    /// Unregister all hotkeys.
    func unregister() {
        if let ref = f5HotkeyRef {
            UnregisterEventHotKey(ref)
            f5HotkeyRef = nil
        }

        if let ref = customHotkeyRef {
            UnregisterEventHotKey(ref)
            customHotkeyRef = nil
        }

        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    /// Update the custom hotkey with new key code and modifiers.
    func updateHotkey(keyCode: UInt32, modifiers: UInt32) {
        settingsService.hotkeyKeyCode = keyCode
        settingsService.hotkeyModifiers = modifiers
        register()
    }

    // MARK: - Dictation Replacement

    /// Configures macOS to allow F5/dictation key usage by SuperWhisper.
    /// Only applies when Force F5 toggle is enabled.
    /// 1. Disables macOS native dictation preferences
    /// 2. Disables the dictation symbolic hotkey (no more popup)
    /// 3. Remaps dictation key → F5 at the HID driver level via hidutil
    static func configureDictationKey(enabled: Bool) {
        guard enabled else {
            print("⏭️ Force F5 disabled, skipping dictation key configuration")
            // Remove any existing hidutil remapping
            restoreHIDMapping()
            return
        }

        print("🔧 Configuring dictation key replacement...")

        // 1. Disable macOS native dictation via preferences
        let commands: [(domain: String, key: String, value: String)] = [
            ("com.apple.HIToolbox", "AppleDictationAutoEnable", "-int 0"),
            ("com.apple.speech.recognition.AppleSpeechRecognition.prefs", "DictationIMMasterDictationEnabled", "-bool false"),
        ]

        for cmd in commands {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            process.arguments = ["write", cmd.domain, cmd.key] + cmd.value.components(separatedBy: " ")
            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                print("⚠️ Failed to set \(cmd.domain) \(cmd.key): \(error)")
            }
        }
        print("✅ macOS dictation preferences disabled")

        // 2. Disable the dictation symbolic hotkey (key 164) to suppress the popup
        disableDictationShortcut()

        // 3. Remap dictation/microphone key → standard F5 at the HID driver level
        remapDictationKeyToF5()
    }

    /// Uses hidutil to remap the dictation/microphone special function key
    /// to a standard F5 keycode at the HID driver level.
    private static func remapDictationKeyToF5() {
        print("🔧 Remapping dictation key → F5 via hidutil...")

        let json = """
        {"UserKeyMapping":[{"HIDKeyboardModifierMappingSrc":0xC000000CF,"HIDKeyboardModifierMappingDst":0x70000003E}]}
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                print("✅ Dictation key remapped to F5 via hidutil")
            } else {
                print("⚠️ hidutil returned status: \(process.terminationStatus)")
            }
        } catch {
            print("❌ Failed to run hidutil: \(error)")
        }
    }

    /// Removes hidutil key remapping (restores original dictation key behavior).
    private static func restoreHIDMapping() {
        let json = """
        {"UserKeyMapping":[]}
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hidutil")
        process.arguments = ["property", "--set", json]
        do {
            try process.run()
            process.waitUntilExit()
            print("✅ HID key mapping restored")
        } catch {
            print("⚠️ Failed to restore HID mapping: \(error)")
        }
    }

    /// Disables the dictation symbolic hotkey (key 164) via PlistBuddy.
    private static func disableDictationShortcut() {
        print("🔧 Disabling dictation keyboard shortcut...")

        let plistPath = NSHomeDirectory() + "/Library/Preferences/com.apple.symbolichotkeys.plist"

        let plistBuddy = Process()
        plistBuddy.executableURL = URL(fileURLWithPath: "/usr/libexec/PlistBuddy")
        plistBuddy.arguments = ["-c", "Set :AppleSymbolicHotKeys:164:enabled false", plistPath]
        do {
            try plistBuddy.run()
            plistBuddy.waitUntilExit()
            if plistBuddy.terminationStatus == 0 {
                print("✅ Dictation shortcut (symbolic hotkey 164) disabled")
            } else {
                print("⚠️ PlistBuddy returned status: \(plistBuddy.terminationStatus)")
            }
        } catch {
            print("❌ Failed to run PlistBuddy: \(error)")
        }

        // Activate the settings change immediately
        let activate = Process()
        activate.executableURL = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings")
        activate.arguments = ["-u"]
        do {
            try activate.run()
            activate.waitUntilExit()
            print("✅ Settings activated")
        } catch {
            print("⚠️ Could not activate settings: \(error)")
        }
    }

    // MARK: - Private Helpers

    private func carbonModifierFlags(from flags: UInt32) -> UInt32 {
        var result: UInt32 = 0
        if flags & UInt32(cmdKey) != 0 { result |= UInt32(cmdKey) }
        if flags & UInt32(shiftKey) != 0 { result |= UInt32(shiftKey) }
        if flags & UInt32(optionKey) != 0 { result |= UInt32(optionKey) }
        if flags & UInt32(controlKey) != 0 { result |= UInt32(controlKey) }
        return result
    }

    private func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for char in string.utf8.prefix(4) {
            result = (result << 8) | OSType(char)
        }
        return result
    }
}
