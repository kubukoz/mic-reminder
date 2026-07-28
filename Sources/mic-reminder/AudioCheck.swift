import CoreAudio
import Foundation

let airpodsNameHint = "AirPods"
let at2020Name = "AT2020USB-X"
let pollInterval: TimeInterval = 10

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

struct AudioState {
    let at2020Connected: Bool
    let airpodsConnected: Bool
    let defaultInputName: String?
}

func currentAudioState() -> AudioState {
    let deviceIDs = allAudioDeviceIDs()
    let defaultInputID = defaultInputDeviceID()

    var at2020Connected = false
    var airpodsConnected = false
    var defaultInputName: String? = nil

    for id in deviceIDs {
        guard let name = deviceName(id) else { continue }

        if name == at2020Name {
            at2020Connected = true
        }
        if name.contains(airpodsNameHint), deviceHasInputStreams(id) {
            airpodsConnected = true
        }
        if id == defaultInputID {
            defaultInputName = name
        }
    }

    return AudioState(
        at2020Connected: at2020Connected,
        airpodsConnected: airpodsConnected,
        defaultInputName: defaultInputName
    )
}

func isZoomInCall() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/ps")
    task.arguments = ["-ax", "-o", "comm"]

    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = Pipe()

    do {
        try task.run()
    } catch {
        return false
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let output = String(data: data, encoding: .utf8) ?? ""

    return output.contains("CptHost")
}

func shouldWarn() -> Bool {
    let audio = currentAudioState()
    let inCall = isZoomInCall()
    let usingAirpods = audio.defaultInputName?.contains(airpodsNameHint) ?? false
    return inCall && usingAirpods && audio.at2020Connected
}
