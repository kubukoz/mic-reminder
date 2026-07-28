import CoreAudio
import Foundation

func allAudioDeviceIDs() -> [AudioDeviceID] {
    var propertySize: UInt32 = 0
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    var status = AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize)
    guard status == noErr else { return [] }

    let deviceCount = Int(propertySize) / MemoryLayout<AudioDeviceID>.size
    var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
    status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceIDs)
    guard status == noErr else { return [] }

    return deviceIDs
}

func deviceName(_ deviceID: AudioDeviceID) -> String? {
    var name: CFString = "" as CFString
    var propertySize = UInt32(MemoryLayout<CFString>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
        AudioObjectGetPropertyData(deviceID, &address, 0, nil, &propertySize, ptr)
    }
    guard status == noErr else { return nil }
    return name as String
}

func deviceHasInputStreams(_ deviceID: AudioDeviceID) -> Bool {
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreams,
        mScope: kAudioObjectPropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain
    )
    var propertySize: UInt32 = 0
    let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &propertySize)
    guard status == noErr else { return false }
    return propertySize > 0
}

func defaultInputDeviceID() -> AudioDeviceID? {
    var deviceID = AudioDeviceID(0)
    var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &propertySize, &deviceID)
    guard status == noErr else { return nil }
    return deviceID
}

// Names of all currently connected devices that have at least one input stream.
func connectedInputDeviceNames() -> [String] {
    allAudioDeviceIDs().compactMap { id in
        guard deviceHasInputStreams(id), let name = deviceName(id) else { return nil }
        return name
    }
}

func currentDefaultInputName() -> String? {
    guard let id = defaultInputDeviceID() else { return nil }
    return deviceName(id)
}

// Adds any currently connected device not already known (in either the
// priority list or the unranked list) to the unranked list, preserving
// existing order in both lists. Call before reading or displaying the lists
// so newly connected devices show up (as unranked, not auto-prioritized).
func reconcileKnownMicNames() {
    let priorityList = Settings.micPriorityList
    var unranked = Settings.unrankedMicNames
    let connectedNames = connectedInputDeviceNames()

    let isKnown: (String) -> Bool = { name in
        priorityList.contains(where: { name.contains($0) || $0.contains(name) })
            || unranked.contains(where: { name.contains($0) || $0.contains(name) })
    }

    for name in connectedNames where !isKnown(name) {
        unranked.append(name)
    }
    Settings.unrankedMicNames = unranked
}

// The highest-priority entry (from Settings.micPriorityList) that has a
// currently connected matching device, if any.
func bestAvailableMicPriorityEntry() -> String? {
    let connectedNames = connectedInputDeviceNames()
    return Settings.micPriorityList.first { entry in
        connectedNames.contains { $0.contains(entry) }
    }
}

func priorityEntry(matching deviceName: String) -> String? {
    Settings.micPriorityList.first { deviceName.contains($0) }
}

func deviceID(forPriorityEntry entry: String) -> AudioDeviceID? {
    allAudioDeviceIDs().first { id in
        guard let name = deviceName(id) else { return false }
        return name.contains(entry)
    }
}

@discardableResult
func setDefaultInputDevice(_ deviceID: AudioDeviceID) -> Bool {
    var mutableDeviceID = deviceID
    var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    let status = AudioObjectSetPropertyData(
        AudioObjectID(kAudioObjectSystemObject),
        &address,
        0,
        nil,
        UInt32(MemoryLayout<AudioDeviceID>.size),
        &mutableDeviceID
    )
    return status == noErr
}

// A better mic is available if a connected device from the priority list
// outranks whatever's currently active. A current input that isn't in the
// priority list at all is treated as ranked below every listed device.
func betterMicEntryThanCurrent() -> String? {
    guard let bestEntry = bestAvailableMicPriorityEntry() else { return nil }

    guard let currentName = currentDefaultInputName(),
          let currentEntry = priorityEntry(matching: currentName)
    else {
        // Current input isn't ranked at all — any available ranked entry is "better".
        return bestEntry
    }

    guard bestEntry != currentEntry,
          let currentIndex = Settings.micPriorityList.firstIndex(of: currentEntry),
          let bestIndex = Settings.micPriorityList.firstIndex(of: bestEntry),
          bestIndex < currentIndex
    else {
        return nil
    }
    return bestEntry
}

// Registers a listener that fires whenever the default input device changes
// or the set of connected audio devices changes (plug/unplug). The handler
// is invoked on the main queue.
func onAudioConfigurationChanged(_ handler: @escaping () -> Void) {
    let systemObject = AudioObjectID(kAudioObjectSystemObject)
    let block: AudioObjectPropertyListenerBlock = { _, _ in
        DispatchQueue.main.async {
            handler()
        }
    }

    var defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(systemObject, &defaultInputAddress, DispatchQueue.main, block)

    var deviceListAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )
    AudioObjectAddPropertyListenerBlock(systemObject, &deviceListAddress, DispatchQueue.main, block)
}
