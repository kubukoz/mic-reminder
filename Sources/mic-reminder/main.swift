import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var timer: Timer!
    private var wasTriggered = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: "mic-reminder")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 280, height: 120)

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.poll()
        }
        poll()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func poll() {
        let triggered = shouldWarn()
        if triggered && !wasTriggered {
            showWarning()
        }
        wasTriggered = triggered
    }

    private func showWarning() {
        guard let button = statusItem.button else { return }

        let label = NSTextField(wrappingLabelWithString: "Zoom call using AirPods as mic while AT2020USB-X is connected — consider switching input!")
        label.font = NSFont.systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        let switchButton = NSButton(title: "Switch to \(at2020Name)", target: self, action: #selector(switchToAT2020))
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
        popover.contentViewController = viewController

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func switchToAT2020() {
        if let deviceID = at2020DeviceID() {
            setDefaultInputDevice(deviceID)
        }
        popover.performClose(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
