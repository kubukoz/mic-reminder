import Foundation

enum Settings {
    private static let defaults = UserDefaults.standard
    private static let micPriorityKey = "micPriorityList"
    private static let unrankedMicsKey = "unrankedMicNames"
    private static let autoSwitchKey = "autoSwitch"
    private static let showMicNameKey = "showMicNameInMenuBar"

    // Highest priority first. Only devices in this list participate in
    // detection. Includes devices not currently connected — their rank is
    // preserved across disconnect/reconnect.
    static var micPriorityList: [String] {
        get { defaults.stringArray(forKey: micPriorityKey) ?? [] }
        set { defaults.set(newValue, forKey: micPriorityKey) }
    }

    // When true, switching to a higher-priority mic happens automatically;
    // when false, the popover warning offers a manual "Switch" button instead.
    static var autoSwitch: Bool {
        get { defaults.object(forKey: autoSwitchKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: autoSwitchKey) }
    }

    // When true, the menu bar item shows the current input device's name next
    // to the icon; when false, only the icon is shown.
    static var showMicNameInMenuBar: Bool {
        get { defaults.object(forKey: showMicNameKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: showMicNameKey) }
    }

    // Known devices not (or no longer) in the priority list. New devices
    // land here by default; the user drags them into the priority list
    // via Preferences to opt them into detection.
    static var unrankedMicNames: [String] {
        get { defaults.stringArray(forKey: unrankedMicsKey) ?? [] }
        set { defaults.set(newValue, forKey: unrankedMicsKey) }
    }
}
