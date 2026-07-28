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
        tableView.rowHeight = 22
        tableView.usesAlternatingRowBackgroundColors = true
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

final class PreferencesWindowController: NSWindowController {
    private let priorityListView = MicNameListView()
    private let unrankedListView = MicNameListView()
    var onSave: (() -> Void)?

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "MicReminder Preferences"
        window.isReleasedWhenClosed = false
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
        guard let contentView = window?.contentView else { return }

        let priorityLabel = NSTextField(wrappingLabelWithString: "Mic priority (drag to reorder, top = most preferred). These devices participate in the switch-input warning.")
        priorityLabel.font = NSFont.systemFont(ofSize: 12)

        let unrankedLabel = NSTextField(wrappingLabelWithString: "Other known mics (drag up to add to priority list). Greyed out = not currently connected.")
        unrankedLabel.font = NSFont.systemFont(ofSize: 12)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"

        let views: [NSView] = [priorityLabel, priorityListView, unrankedLabel, unrankedListView, refreshButton, saveButton]
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        NSLayoutConstraint.activate([
            priorityLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            priorityLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            priorityLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            priorityListView.topAnchor.constraint(equalTo: priorityLabel.bottomAnchor, constant: 8),
            priorityListView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            priorityListView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            priorityListView.heightAnchor.constraint(equalToConstant: 130),

            unrankedLabel.topAnchor.constraint(equalTo: priorityListView.bottomAnchor, constant: 16),
            unrankedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            unrankedLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),

            unrankedListView.topAnchor.constraint(equalTo: unrankedLabel.bottomAnchor, constant: 8),
            unrankedListView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            unrankedListView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            unrankedListView.heightAnchor.constraint(equalToConstant: 110),

            refreshButton.topAnchor.constraint(equalTo: unrankedListView.bottomAnchor, constant: 8),
            refreshButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),

            saveButton.topAnchor.constraint(equalTo: refreshButton.bottomAnchor, constant: 20),
            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -20),
        ])
    }

    @objc private func refresh() {
        reconcileKnownMicNames()
        reloadNames()
    }

    @objc private func save() {
        Settings.micPriorityList = priorityListView.names
        Settings.unrankedMicNames = unrankedListView.names
        onSave?()
        window?.close()
    }
}
