import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var lastTriggeredEntry: String?
    private var showMicNameItem: NSMenuItem?
    private var preferencesWindowController: PreferencesWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let menu = NSMenu()
        let showMicNameItem = NSMenuItem(title: "Show Mic Name", action: #selector(toggleShowMicName), keyEquivalent: "")
        showMicNameItem.state = Settings.showMicNameInMenuBar ? .on : .off
        menu.addItem(showMicNameItem)
        self.showMicNameItem = showMicNameItem
        menu.addItem(NSMenuItem.separator())
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

    @objc private func toggleShowMicName() {
        Settings.showMicNameInMenuBar.toggle()
        updateStatusItem(betterEntry: betterMicEntryThanCurrent())
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // Switching the default input immediately from within the CoreAudio
    // config-change callback is flaky — the HAL can still be mid-transaction
    // (e.g. reacting to the same plug/unplug event we're reacting to) and
    // silently ignores or reverts the set. A short delay lets that settle.
    private static let autoSwitchDelay: TimeInterval = 1.0

    // Long device names ("MacBook Pro Microphone") would crowd out the rest of
    // the menu bar, so the title is truncated with an ellipsis. The full name
    // stays available via the button's tooltip.
    private static let maxTitleLength = 18

    private func updateStatusItem(betterEntry: String?) {
        guard let button = statusItem.button else { return }

        let currentName = currentDefaultInputName()
        let symbol = betterEntry == nil ? "mic" : "mic.badge.xmark"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: currentName ?? "mic-reminder")

        if Settings.showMicNameInMenuBar {
            let name = currentName ?? "No input"
            button.title = name.count > Self.maxTitleLength
                ? String(name.prefix(Self.maxTitleLength - 1)) + "…"
                : name
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
        button.toolTip = currentName.map { "Current input: \($0)" } ?? "No audio input device"

        showMicNameItem?.state = Settings.showMicNameInMenuBar ? .on : .off
    }

    private func poll() {
        reconcileKnownMicNames()
        let betterEntry = betterMicEntryThanCurrent()
        updateStatusItem(betterEntry: betterEntry)
        if let betterEntry, betterEntry != lastTriggeredEntry {
            if Settings.autoSwitch {
                let previousName = currentDefaultInputName() ?? "current mic"
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.autoSwitchDelay) { [weak self] in
                    guard let self, let id = deviceID(forPriorityEntry: betterEntry) else { return }
                    setDefaultInputDevice(id)
                    updateStatusItem(betterEntry: betterMicEntryThanCurrent())
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

        let icon = NSImageView(image: NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .controlAccentColor
        icon.symbolConfiguration = .init(pointSize: 18, weight: .medium)

        let label = NSTextField(wrappingLabelWithString: "Switched from \(previousName) to \(betterEntry) automatically.")
        label.font = NSFont.systemFont(ofSize: 13)

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10

        popover.contentSize = NSSize(width: 300, height: 76)
        let viewController = glassPopoverContent(
            Glass.wrap(row, padding: 14),
            size: popover.contentSize
        )
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

        let icon = NSImageView(image: NSImage(systemSymbolName: "mic.badge.xmark", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .systemOrange
        icon.symbolConfiguration = .init(pointSize: 18, weight: .medium)

        let label = NSTextField(wrappingLabelWithString: "Using \(currentName), but \(betterEntry) is available and ranked higher — consider switching input!")
        label.font = NSFont.systemFont(ofSize: 13)

        let row = NSStackView(views: [icon, label])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 10

        let switchButton = NSButton(title: "Switch to \(betterEntry)", target: self, action: #selector(switchToBetterMic))
        Glass.style(switchButton, prominent: true)

        let stack = NSStackView(views: [row, switchButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12

        popover.contentSize = NSSize(width: 300, height: 132)
        popover.contentViewController = glassPopoverContent(
            Glass.wrap(stack, padding: 14),
            size: popover.contentSize
        )

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    // NSPopover draws its own opaque background, which would sit behind our
    // glass and flatten it. Hosting the glass in a transparent content view
    // controller and clearing the popover's own material lets the glass be
    // the only thing the user sees.
    private func glassPopoverContent(_ glass: NSView, size: NSSize) -> NSViewController {
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        glass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(glass)
        NSLayoutConstraint.activate([
            glass.topAnchor.constraint(equalTo: container.topAnchor),
            glass.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            glass.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            glass.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        let viewController = NSViewController()
        viewController.view = Glass.container(container)
        return viewController
    }

    @objc private func switchToBetterMic() {
        if let entry = lastTriggeredEntry, let id = deviceID(forPriorityEntry: entry) {
            setDefaultInputDevice(id)
            updateStatusItem(betterEntry: betterMicEntryThanCurrent())
        }
        popover.performClose(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
