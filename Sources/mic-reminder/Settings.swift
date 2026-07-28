import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard
    private static let micPriorityKey = "micPriorityList"
    private static let unrankedMicsKey = "unrankedMicNames"

    // Highest priority first. Only devices in this list participate in
    // detection. Includes devices not currently connected — their rank is
    // preserved across disconnect/reconnect.
    static var micPriorityList: [String] {
        get { defaults.stringArray(forKey: micPriorityKey) ?? [] }
        set { defaults.set(newValue, forKey: micPriorityKey) }
    }

    // Known devices not (or no longer) in the priority list. New devices
    // land here by default; the user drags them into the priority list
    // via Preferences to opt them into detection.
    static var unrankedMicNames: [String] {
        get { defaults.stringArray(forKey: unrankedMicsKey) ?? [] }
        set { defaults.set(newValue, forKey: unrankedMicsKey) }
    }
}
