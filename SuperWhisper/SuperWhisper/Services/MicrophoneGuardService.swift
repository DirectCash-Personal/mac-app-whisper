import AppKit
import CoreAudio
import os

/// Keeps a just-connected microphone (AirPods, other Bluetooth, iPhone mic) from taking over the default input.
/// Decision logic adapted from MicGuard (github.com/pszypowicz/MicGuard, MIT): a default-input switch to a device
/// that appeared less than `newDeviceWindowSeconds` ago, or within `settleSeconds` of a device list change, is a
/// hijack and reverts to the preferred input; any later switch is the user's choice and becomes the new preferred.
/// Only CoreAudio listeners, no timers or polling.
final class MicrophoneGuardService: ObservableObject {
    private let logger = Logger(subsystem: "com.superwhisper.app", category: "microphone-guard")
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let enabled = "SW_MicrophoneGuardEnabled"
        static let preferredInputUID = "SW_MicrophoneGuardPreferredInputUID"
    }

    /// After a device connects or disconnects, macOS default-input switches arrive in a burst.
    private let settleSeconds: CFAbsoluteTime = 3.0
    private let newDeviceWindowSeconds: Double = 10.0

    private var knownInputUIDs = Set<String>()
    private var lastDeviceListChangeTime: CFAbsoluteTime = 0
    private var currentInputUID = ""
    private var recentRevertTimes: [CFAbsoluteTime] = []

    @Published private(set) var lastBlockedSummary: String?

    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Keys.enabled)
            logger.info("guard \(self.isEnabled ? "enabled" : "disabled", privacy: .public)")
            if isEnabled { enforcePreferredIfAvailable(reason: "guard enabled") }
        }
    }

    @Published private(set) var preferredInputUID: String {
        didSet { defaults.set(preferredInputUID, forKey: Keys.preferredInputUID) }
    }

    init() {
        isEnabled = defaults.object(forKey: Keys.enabled) as? Bool ?? true
        preferredInputUID = defaults.string(forKey: Keys.preferredInputUID) ?? ""
    }

    func start() {
        var defaultInputAddress = CoreAudioInputDevices.address(kAudioHardwarePropertyDefaultInputDevice)
        AudioObjectAddPropertyListenerBlock(CoreAudioInputDevices.systemObjectID, &defaultInputAddress, .main) { [weak self] _, _ in
            self?.handleDefaultInputChanged()
        }
        var deviceListAddress = CoreAudioInputDevices.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(CoreAudioInputDevices.systemObjectID, &deviceListAddress, .main) { [weak self] _, _ in
            self?.handleDeviceListChanged()
        }

        let inputDevices = CoreAudioInputDevices.listInputDevices()
        knownInputUIDs = Set(inputDevices.map(\.deviceUID))
        let currentInput = CoreAudioInputDevices.currentDefaultInput()
        currentInputUID = currentInput?.deviceUID ?? ""
        if preferredInputUID.isEmpty {
            // First run: the current input unless it is already Bluetooth; then the built-in microphone.
            let initialPreferred = (currentInput?.isBluetooth == false ? currentInput : nil)
                ?? inputDevices.first(where: \.isBuiltIn) ?? currentInput
            preferredInputUID = initialPreferred?.deviceUID ?? ""
        }
        logger.info("started; current='\(currentInput?.deviceName ?? "-", privacy: .public)' preferred='\(self.preferredInputUID, privacy: .public)'")
        if isEnabled { enforcePreferredIfAvailable(reason: "launch") }
    }

    var currentInputName: String { CoreAudioInputDevices.currentDefaultInput()?.deviceName ?? "-" }
    var inputDevices: [AudioInputDevice] { CoreAudioInputDevices.listInputDevices() }

    func choosePreferredInput(deviceUID: String) {
        guard let device = inputDevices.first(where: { $0.deviceUID == deviceUID }) else { return }
        preferredInputUID = device.deviceUID
        if CoreAudioInputDevices.setDefaultInput(device) { currentInputUID = device.deviceUID }
        logger.info("preferred chosen: '\(device.deviceName, privacy: .public)'")
    }

    private func handleDeviceListChanged() {
        let inputDevices = CoreAudioInputDevices.listInputDevices()
        lastDeviceListChangeTime = CFAbsoluteTimeGetCurrent()
        // Only departed devices leave the known set; a new one is acknowledged by the default-input decision
        // or, if macOS switches nothing, after the new-device window (so a later manual pick is respected).
        knownInputUIDs.formIntersection(inputDevices.map(\.deviceUID))
        let addedInputUIDs = Set(inputDevices.map(\.deviceUID)).subtracting(knownInputUIDs)
        if !addedInputUIDs.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + newDeviceWindowSeconds) { [weak self] in
                guard let self else { return }
                let stillPresentUIDs = Set(CoreAudioInputDevices.listInputDevices().map(\.deviceUID))
                self.knownInputUIDs.formUnion(addedInputUIDs.intersection(stillPresentUIDs))
            }
        }
        if !inputDevices.contains(where: { $0.deviceUID == currentInputUID }),
           let fallbackInput = CoreAudioInputDevices.currentDefaultInput() {
            knownInputUIDs.insert(fallbackInput.deviceUID)
            currentInputUID = fallbackInput.deviceUID
            // Current input left and macOS fell back to Bluetooth: try the preferred or the built-in.
            if isEnabled, fallbackInput.isBluetooth { enforcePreferredIfAvailable(reason: "current input disconnected") }
        }
    }

    private func handleDefaultInputChanged() {
        guard let newInput = CoreAudioInputDevices.currentDefaultInput(), newInput.deviceUID != currentInputUID else { return }
        let isNewDevice = !knownInputUIDs.contains(newInput.deviceUID)
        knownInputUIDs.formUnion(CoreAudioInputDevices.listInputDevices().map(\.deviceUID))
        let isSettled = CFAbsoluteTimeGetCurrent() - lastDeviceListChangeTime >= settleSeconds

        if isSettled && !isNewDevice {
            preferredInputUID = newInput.deviceUID
            currentInputUID = newInput.deviceUID
            logger.info("manual switch accepted: '\(newInput.deviceName, privacy: .public)' is the new preferred")
        } else if !isEnabled || newInput.deviceUID == preferredInputUID {
            currentInputUID = newInput.deviceUID
        } else if revertToPreferred(blockedInput: newInput, reason: isNewDevice ? "new device" : "settle window") {
            lastDeviceListChangeTime = CFAbsoluteTimeGetCurrent()
        } else {
            currentInputUID = newInput.deviceUID
        }
    }

    private func enforcePreferredIfAvailable(reason: String) {
        guard let currentInput = CoreAudioInputDevices.currentDefaultInput(), currentInput.deviceUID != preferredInputUID else { return }
        _ = revertToPreferred(blockedInput: currentInput, reason: reason)
    }

    /// Back to the preferred input; without it and with Bluetooth on the input, the built-in microphone.
    private func revertToPreferred(blockedInput: AudioInputDevice, reason: String) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        recentRevertTimes = recentRevertTimes.filter { now - $0 < 30 } + [now]
        guard recentRevertTimes.count <= 20 else {
            logger.error("over 20 reverts in 30 s; macOS keeps choosing '\(blockedInput.deviceName, privacy: .public)', pausing until the next switch")
            return false
        }
        let inputDevices = CoreAudioInputDevices.listInputDevices()
        let targetInput = inputDevices.first(where: { $0.deviceUID == preferredInputUID })
            ?? (blockedInput.isBluetooth ? inputDevices.first(where: \.isBuiltIn) : nil)
        guard let targetInput, targetInput.deviceUID != blockedInput.deviceUID,
              CoreAudioInputDevices.setDefaultInput(targetInput) else { return false }
        currentInputUID = targetInput.deviceUID
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        lastBlockedSummary = "\(blockedInput.deviceName) at \(timeFormatter.string(from: Date()))"
        logger.info("blocked '\(blockedInput.deviceName, privacy: .public)' (\(reason, privacy: .public)); input back on '\(targetInput.deviceName, privacy: .public)'")
        return true
    }
}

// MARK: - CoreAudio

struct AudioInputDevice {
    let deviceID: AudioDeviceID
    let deviceUID: String
    let deviceName: String
    let transportType: UInt32

    var isBluetooth: Bool {
        transportType == kAudioDeviceTransportTypeBluetooth || transportType == kAudioDeviceTransportTypeBluetoothLE
    }
    var isBuiltIn: Bool { transportType == kAudioDeviceTransportTypeBuiltIn }
}

enum CoreAudioInputDevices {
    static let systemObjectID = AudioObjectID(kAudioObjectSystemObject)

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func listInputDevices() -> [AudioInputDevice] {
        var propertyAddress = address(kAudioHardwarePropertyDevices)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(systemObjectID, &propertyAddress, 0, nil, &dataSize) == noErr else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: Int(dataSize) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(systemObjectID, &propertyAddress, 0, nil, &dataSize, &deviceIDs) == noErr else { return [] }
        return deviceIDs.compactMap(inputDevice(for:))
    }

    static func inputDevice(for deviceID: AudioDeviceID) -> AudioInputDevice? {
        guard deviceID != kAudioObjectUnknown, inputChannelCount(deviceID) > 0, !isHidden(deviceID),
              let deviceUID = stringProperty(deviceID, kAudioDevicePropertyDeviceUID),
              let deviceName = stringProperty(deviceID, kAudioObjectPropertyName) else { return nil }
        var transportType: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = address(kAudioDevicePropertyTransportType)
        AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &transportType)
        return AudioInputDevice(deviceID: deviceID, deviceUID: deviceUID, deviceName: deviceName, transportType: transportType)
    }

    static func currentDefaultInput() -> AudioInputDevice? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var propertyAddress = address(kAudioHardwarePropertyDefaultInputDevice)
        guard AudioObjectGetPropertyData(systemObjectID, &propertyAddress, 0, nil, &dataSize, &deviceID) == noErr else { return nil }
        return inputDevice(for: deviceID)
    }

    @discardableResult
    static func setDefaultInput(_ device: AudioInputDevice) -> Bool {
        var deviceID = device.deviceID
        var propertyAddress = address(kAudioHardwarePropertyDefaultInputDevice)
        return AudioObjectSetPropertyData(systemObjectID, &propertyAddress, 0, nil,
                                          UInt32(MemoryLayout<AudioDeviceID>.size), &deviceID) == noErr
    }

    private static func inputChannelCount(_ deviceID: AudioDeviceID) -> Int {
        var propertyAddress = address(kAudioDevicePropertyStreamConfiguration, kAudioDevicePropertyScopeInput)
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &propertyAddress, 0, nil, &dataSize) == noErr, dataSize > 0 else { return 0 }
        let bufferListPointer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { bufferListPointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, bufferListPointer) == noErr else { return 0 }
        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer.assumingMemoryBound(to: AudioBufferList.self))
        return bufferList.reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    private static func isHidden(_ deviceID: AudioDeviceID) -> Bool {
        var hiddenFlag: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        var propertyAddress = address(kAudioDevicePropertyIsHidden)
        return AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &hiddenFlag) == noErr && hiddenFlag != 0
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var propertyAddress = address(selector)
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(deviceID, &propertyAddress, 0, nil, &dataSize, &value) == noErr,
              let cfString = value?.takeRetainedValue() else { return nil }
        return cfString as String
    }
}
