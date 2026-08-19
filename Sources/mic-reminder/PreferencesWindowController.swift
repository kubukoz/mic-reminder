import AppKit

private let dragType = NSPasteboard.PasteboardType("com.kubukoz.mic-reminder.micname")

// A single-column, drag-and-drop-enabled list of mic names. Reordering
// within the list and drag-out (to another MicNameListView) are both
// supported; the owner decides what happens via onReorder/onRemove/onDrop.
final class MicNameListView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    var names: [String] = [] {
        didSet { tableView.reloadData() }
    }
    var greyedOutNames: Set<String> = [] {
        didSet { tableView.reloadData() }
    }
    var currentMicName: String? {
        didSet { tableView.reloadData() }
    }
    /// Called with (sourceIndex, destinationIndex) when a row is dragged within this list.
    var onReorder: ((Int, Int) -> Void)?
    /// Called with the name when a row is dragged out and accepted by another list.
    var onRemove: ((String) -> Void)?
    /// Called with (name, destinationIndex) when a row from another list is dropped here.
    var onExternalDrop: ((String, Int) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.hasVerticalScroller = true
        scrollView.documentView = tableView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("mic"))
        column.width = 260
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.registerForDraggedTypes([dragType])
        tableView.rowHeight = 24
        // Glass supplies the backing material, so the table draws no ground of
        // its own — alternating row colours would read as opaque stripes on it.
        tableView.usesAlternatingRowBackgroundColors = !Glass.isAvailable
        tableView.backgroundColor = .clear
        tableView.style = .inset
        scrollView.drawsBackground = false
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        names.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let name = names[row]
        let isCurrent = currentMicName.map { $0.contains(name) } ?? false
        let field = NSTextField(labelWithString: isCurrent ? "\(name) (current)" : name)
        field.textColor = greyedOutNames.contains(name) ? .disabledControlTextColor : .labelColor
        field.font = isCurrent ? NSFont.boldSystemFont(ofSize: 13) : NSFont.systemFont(ofSize: 13)
        return field
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(names[row], forType: dragType)
        item.setString(ObjectIdentifier(self).debugDescription, forType: .string)
        return item
    }

    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        dropOperation == .above ? .move : []
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        guard let item = info.draggingPasteboard.pasteboardItems?.first,
              let name = item.string(forType: dragType)
        else {
            return false
        }

        if let sourceRow = names.firstIndex(of: name), info.draggingSource as? NSTableView === tableView {
            var targetRow = row
            names.remove(at: sourceRow)
            if sourceRow < targetRow {
                targetRow -= 1
            }
            names.insert(name, at: min(targetRow, names.count))
            onReorder?(sourceRow, targetRow)
        } else {
            onExternalDrop?(name, min(row, names.count))
        }
        return true
    }
}

// A purely decorative backdrop. NSVisualEffectView swallows clicks by
// default, which would steal titlebar drags (the content view extends under
// the titlebar once titlebarAppearsTransparent is set), so this one opts out
// of hit-testing entirely.
private final class BackdropView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class PreferencesWindowController: NSWindowController {
    private let priorityListView = MicNameListView()
    private let unrankedListView = MicNameListView()
    private let autoSwitchCheckbox = NSButton(checkboxWithTitle: "Automatically switch to the higher-priority mic", target: nil, action: nil)
    private let showMicNameCheckbox = NSButton(checkboxWithTitle: "Show current mic name in the menu bar", target: nil, action: nil)
    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 460),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MicReminder Preferences"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        // The window keeps a real background colour on purpose. Setting it to
        // .clear (with isOpaque = false) leaves the titlebar with no material
        // to hit-test, which silently kills title-drag; the translucency comes
        // from the backdrop view in buildUI() instead.
        window.backgroundColor = .windowBackgroundColor
        self.init(window: window)
        reloadNames()
        buildUI()
        wireDragHandlers()
        window.center()
    }

    private func reloadNames() {
        let connected = Set(connectedInputDeviceNames())
        func isConnected(_ entry: String) -> Bool {
            connected.contains { $0.contains(entry) }
        }
        let currentMicName = currentDefaultInputName()

        priorityListView.names = Settings.micPriorityList
        priorityListView.greyedOutNames = Set(Settings.micPriorityList.filter { !isConnected($0) })
        priorityListView.currentMicName = currentMicName

        unrankedListView.names = Settings.unrankedMicNames
        unrankedListView.greyedOutNames = Set(Settings.unrankedMicNames.filter { !isConnected($0) })
        unrankedListView.currentMicName = currentMicName

        autoSwitchCheckbox.state = Settings.autoSwitch ? .on : .off
        showMicNameCheckbox.state = Settings.showMicNameInMenuBar ? .on : .off
    }

    private func wireDragHandlers() {
        priorityListView.onExternalDrop = { [weak self] name, index in
            guard let self else { return }
            unrankedListView.names.removeAll { $0 == name }
            priorityListView.names.insert(name, at: min(index, priorityListView.names.count))
            refreshGreyedOut()
        }
        unrankedListView.onExternalDrop = { [weak self] name, index in
            guard let self else { return }
            priorityListView.names.removeAll { $0 == name }
            unrankedListView.names.insert(name, at: min(index, unrankedListView.names.count))
            refreshGreyedOut()
        }
    }

    private func refreshGreyedOut() {
        let connected = Set(connectedInputDeviceNames())
        func isConnected(_ entry: String) -> Bool {
            connected.contains { $0.contains(entry) }
        }
        priorityListView.greyedOutNames = Set(priorityListView.names.filter { !isConnected($0) })
        unrankedListView.greyedOutNames = Set(unrankedListView.names.filter { !isConnected($0) })
    }

    private func buildUI() {
        guard let window,
              let contentView = window.contentView,
              let contentLayoutGuide = window.contentLayoutGuide as? NSLayoutGuide
        else { return }

        // A window-background visual effect view is what actually lets the
        // Liquid Glass panes above it sample something — glass over an opaque
        // window background just looks like a flat rounded rectangle.
        let backdrop = BackdropView()
        backdrop.material = .hudWindow
        backdrop.blendingMode = .behindWindow
        backdrop.state = .active
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: contentView.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])

        let priorityLabel = sectionLabel("Mic priority (drag to reorder, top = most preferred). These devices participate in the switch-input warning.")
        let unrankedLabel = sectionLabel("Other known mics (drag up to add to priority list). Greyed out = not currently connected.")

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        Glass.style(refreshButton)

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        Glass.style(saveButton, prominent: true)

        // Each list gets its own glass pane; the container merges the two when
        // they drift within `spacing` of each other and batches the render.
        let priorityPane = Glass.wrap(priorityListView, padding: 6)
        let unrankedPane = Glass.wrap(unrankedListView, padding: 6)
        priorityListView.heightAnchor.constraint(equalToConstant: 130).isActive = true
        unrankedListView.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let panes = NSStackView(views: [priorityLabel, priorityPane, unrankedLabel, unrankedPane])
        panes.orientation = .vertical
        panes.alignment = .leading
        panes.spacing = 10
        panes.setCustomSpacing(16, after: priorityPane)

        let glassGroup = Glass.container(panes, spacing: 24)

        let checkboxes = NSStackView(views: [autoSwitchCheckbox, showMicNameCheckbox])
        checkboxes.orientation = .vertical
        checkboxes.alignment = .leading
        checkboxes.spacing = 8

        let buttons = NSStackView(views: [refreshButton, NSView(), saveButton])
        buttons.orientation = .horizontal
        buttons.spacing = 12

        let root = NSStackView(views: [glassGroup, checkboxes, buttons])
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 18
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            // Below the titlebar, not under it — titlebarAppearsTransparent
            // extends contentView upward, and content laid out in that strip
            // would cover the title and swallow window drags.
            root.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor, constant: 16),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            root.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),

            panes.widthAnchor.constraint(equalTo: root.widthAnchor),
            buttons.widthAnchor.constraint(equalTo: root.widthAnchor),
            priorityPane.widthAnchor.constraint(equalTo: panes.widthAnchor),
            unrankedPane.widthAnchor.constraint(equalTo: panes.widthAnchor),
            priorityLabel.widthAnchor.constraint(equalTo: panes.widthAnchor),
            unrankedLabel.widthAnchor.constraint(equalTo: panes.widthAnchor),
        ])
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        return label
    }

    @objc private func refresh() {
        reconcileKnownMicNames()
        reloadNames()
    }

    @objc private func save() {
        Settings.micPriorityList = priorityListView.names
        Settings.unrankedMicNames = unrankedListView.names
        Settings.autoSwitch = autoSwitchCheckbox.state == .on
        Settings.showMicNameInMenuBar = showMicNameCheckbox.state == .on
        onSave?()
        window?.close()
    }
}
