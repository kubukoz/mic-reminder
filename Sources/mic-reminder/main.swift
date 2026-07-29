import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var lastTriggeredEntry: String?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "mic-reminder")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(showPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 120)

        reconcileKnownMicNames()
        onAudioConfigurationChanged { [weak self] in
            self?.poll()
        }
        poll()
    }

    @objc private func showPreferences() {
        if let controller = preferencesWindowController, controller.window?.isVisible == true {
            controller.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        reconcileKnownMicNames()
        let controller = PreferencesWindowController()
        controller.onSave = { [weak self] in
            self?.poll()
        }
        preferencesWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // Switching the default input immediately from within the CoreAudio
    // config-change callback is flaky — the HAL can still be mid-transaction
    // (e.g. reacting to the same plug/unplug event we're reacting to) and
    // silently ignores or reverts the set. A short delay lets that settle.
    private static let autoSwitchDelay: TimeInterval = 1.0

    private func poll() {
        reconcileKnownMicNames()
        let betterEntry = betterMicEntryThanCurrent()
        if let betterEntry, betterEntry != lastTriggeredEntry {
            if Settings.autoSwitch {
                let previousName = currentDefaultInputName() ?? "current mic"
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoSwitchDelay) { [weak self] in
                    guard let self, let id = deviceID(forPriorityEntry: betterEntry) else { return }
                    setDefaultInputDevice(id)
                    showAutoSwitchNotice(from: previousName, to: betterEntry)
                }
            } else {
                showWarning(betterEntry: betterEntry)
            }
        }
        lastTriggeredEntry = betterEntry
    }

    private func showAutoSwitchNotice(from previousName: String, to betterEntry: String) {
        guard let button = statusItem.button else { return }

        let label = NSTextField(wrappingLabelWithString: "Switched from \(previousName) to \(betterEntry) automatically.")
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 60))
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        let viewController = NSViewController()
        viewController.view = container
        popover.contentSize = NSSize(width: 280, height: 60)
        popover.contentViewController = viewController

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self, weak viewController] in
            guard let self, let viewController, popover.contentViewController === viewController else { return }
            popover.performClose(nil)
        }
    }

    private func showWarning(betterEntry: String) {
        guard let button = statusItem.button else { return }

        let currentName = currentDefaultInputName() ?? "current mic"
        let label = NSTextField(wrappingLabelWithString: "Using \(currentName), but \(betterEntry) is available and ranked higher — consider switching input!")
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        let switchButton = NSButton(title: "Switch to \(betterEntry)", target: self, action: #selector(switchToBetterMic))
        switchButton.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 120))
        container.addSubview(label)
        container.addSubview(switchButton)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),

            switchButton.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            switchButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 12),
            switchButton.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        let viewController = NSViewController()
        viewController.view = container
        popover.contentSize = NSSize(width: 280, height: 120)
        popover.contentViewController = viewController

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func switchToBetterMic() {
        if let entry = lastTriggeredEntry, let id = deviceID(forPriorityEntry: entry) {
            setDefaultInputDevice(id)
        }
        popover.performClose(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
