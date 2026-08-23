import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum ArchiveSortColumn: String, CaseIterable {
    case name = "Name"
    case kind = "Kind"
    case size = "Size"
    case packed = "Packed"
    case ratio = "Ratio"
    case modified = "Modified"
}

func archiveItemKindDescription(_ item: ArchiveItem) -> String {
    if item.isDirectory { return "Folder" }
    let ext = (item.name as NSString).pathExtension
    if !ext.isEmpty, let type = UTType(filenameExtension: ext), let description = type.localizedDescription {
        return description
    }
    return "Document"
}

private let archiveModifiedDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter
}()

struct ArchiveContentsTable: View {
    @ObservedObject var archiveModel: ArchiveModel
    @Binding var selectedItems: Set<String>
    @Binding var searchText: String
    var onDropFiles: ([URL]) -> Void

    @State private var sortColumn: ArchiveSortColumn = .name
    @State private var sortAscending = true

    var body: some View {
        ArchiveContentsTableViewWrapper(
            items: filteredAndSortedItems,
            selectedItems: $selectedItems,
            sortColumn: $sortColumn,
            sortAscending: $sortAscending,
            onDoubleClick: { item in
                if item.isDirectory {
                    archiveModel.navigateToPath(item.path)
                }
            },
            onDropFiles: onDropFiles
        )
    }

    private var filteredAndSortedItems: [ArchiveItem] {
        var items = archiveModel.currentItems

        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }

        items.sort { first, second in
            let result: Bool
            switch sortColumn {
            case .name:
                result = first.name.localizedStandardCompare(second.name) == .orderedAscending
            case .kind:
                result = archiveItemKindDescription(first) < archiveItemKindDescription(second)
            case .size:
                result = (first.size ?? 0) < (second.size ?? 0)
            case .packed:
                result = (first.packedSize ?? 0) < (second.packedSize ?? 0)
            case .ratio:
                result = (first.ratio ?? -1) < (second.ratio ?? -1)
            case .modified:
                result = (first.dateModified ?? .distantPast) < (second.dateModified ?? .distantPast)
            }
            return sortAscending ? result : !result
        }

        // Directories first, preserving the sort above within each group.
        var directories: [ArchiveItem] = []
        var files: [ArchiveItem] = []
        for item in items {
            if item.isDirectory { directories.append(item) } else { files.append(item) }
        }
        return directories + files
    }
}

struct ArchiveContentsTableViewWrapper: NSViewRepresentable {
    let items: [ArchiveItem]
    @Binding var selectedItems: Set<String>
    @Binding var sortColumn: ArchiveSortColumn
    @Binding var sortAscending: Bool
    let onDoubleClick: (ArchiveItem) -> Void
    let onDropFiles: ([URL]) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView

        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 8, height: 2)

        func addColumn(_ identifier: String, title: String, minWidth: CGFloat, width: CGFloat, rightAligned: Bool = false) {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.minWidth = minWidth
            column.width = width
            if rightAligned {
                column.headerCell.alignment = .right
            }
            tableView.addTableColumn(column)
        }

        addColumn("Name", title: "Name", minWidth: 150, width: 220)
        tableView.tableColumns[0].resizingMask = [.autoresizingMask, .userResizingMask]
        addColumn("Kind", title: "Kind", minWidth: 100, width: 130)
        addColumn("Size", title: "Size", minWidth: 70, width: 80, rightAligned: true)
        addColumn("Packed", title: "Packed", minWidth: 70, width: 80, rightAligned: true)
        addColumn("Ratio", title: "Ratio", minWidth: 50, width: 60, rightAligned: true)
        addColumn("Modified", title: "Modified", minWidth: 140, width: 160, rightAligned: true)

        let dataSource = ArchiveContentsDataSource(items: items)
        context.coordinator.dataSource = dataSource
        context.coordinator.tableView = tableView
        context.coordinator.onDoubleClick = onDoubleClick
        tableView.dataSource = dataSource
        tableView.delegate = context.coordinator

        // Fixes a longstanding bug where double-click-to-navigate never fired: AppKit only
        // calls -doubleAction when target/doubleAction are actually wired up.
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))

        let dropScrollView = DropAcceptingScrollView(scrollView: scrollView)
        dropScrollView.onDropFiles = onDropFiles

        return dropScrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let dropScrollView = nsView as? DropAcceptingScrollView,
              let tableView = dropScrollView.documentView as? NSTableView,
              let dataSource = context.coordinator.dataSource else {
            return
        }

        dataSource.items = items
        context.coordinator.onDoubleClick = onDoubleClick
        dropScrollView.onDropFiles = onDropFiles
        tableView.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedItems: $selectedItems, sortColumn: $sortColumn, sortAscending: $sortAscending)
    }

    final class Coordinator: NSObject, NSTableViewDelegate {
        @Binding var selectedItems: Set<String>
        @Binding var sortColumn: ArchiveSortColumn
        @Binding var sortAscending: Bool
        var dataSource: ArchiveContentsDataSource?
        weak var tableView: NSTableView?
        var onDoubleClick: ((ArchiveItem) -> Void)?

        init(selectedItems: Binding<Set<String>>, sortColumn: Binding<ArchiveSortColumn>, sortAscending: Binding<Bool>) {
            self._selectedItems = selectedItems
            self._sortColumn = sortColumn
            self._sortAscending = sortAscending
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let dataSource, row < dataSource.items.count else { return nil }

            let item = dataSource.items[row]
            let columnId = tableColumn?.identifier.rawValue ?? ""
            let identifier = NSUserInterfaceItemIdentifier("\(columnId)Cell")

            var cellView = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            if cellView == nil {
                cellView = NSTableCellView()
                cellView?.identifier = identifier

                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.lineBreakMode = .byTruncatingTail
                cellView?.textField = textField
                cellView?.addSubview(textField)

                if columnId == "Name" {
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    imageView.imageScaling = .scaleProportionallyDown
                    imageView.identifier = NSUserInterfaceItemIdentifier("icon")
                    cellView?.addSubview(imageView)

                    let chevron = NSImageView()
                    chevron.translatesAutoresizingMaskIntoConstraints = false
                    chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
                    chevron.contentTintColor = .tertiaryLabelColor
                    chevron.symbolConfiguration = .init(pointSize: 9, weight: .medium)
                    chevron.identifier = NSUserInterfaceItemIdentifier("chevron")
                    cellView?.addSubview(chevron)

                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                        imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 16),
                        imageView.heightAnchor.constraint(equalToConstant: 16),

                        chevron.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                        chevron.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                        chevron.widthAnchor.constraint(equalToConstant: 8),

                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                        textField.trailingAnchor.constraint(lessThanOrEqualTo: chevron.leadingAnchor, constant: -4),
                        textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                    ])
                } else {
                    NSLayoutConstraint.activate([
                        textField.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                        textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                        textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                    ])
                }
            }

            switch columnId {
            case "Name":
                let icon: NSImage
                if item.isDirectory {
                    icon = NSWorkspace.shared.icon(for: .folder)
                } else {
                    let ext = (item.name as NSString).pathExtension
                    let type = ext.isEmpty ? .data : (UTType(filenameExtension: ext) ?? .data)
                    icon = NSWorkspace.shared.icon(for: type)
                }
                icon.size = NSSize(width: 16, height: 16)
                if let imageView = cellView?.subviews.first(where: { $0.identifier?.rawValue == "icon" }) as? NSImageView {
                    imageView.image = icon
                }
                if let chevron = cellView?.subviews.first(where: { $0.identifier?.rawValue == "chevron" }) as? NSImageView {
                    chevron.isHidden = !item.isDirectory
                }
                cellView?.textField?.stringValue = item.name

            case "Kind":
                cellView?.textField?.stringValue = archiveItemKindDescription(item)

            case "Size":
                cellView?.textField?.stringValue = item.size.map(formattedByteCount) ?? (item.isDirectory ? "—" : "")
                cellView?.textField?.alignment = .right

            case "Packed":
                cellView?.textField?.stringValue = item.packedSize.map(formattedByteCount) ?? "—"
                cellView?.textField?.alignment = .right

            case "Ratio":
                if let ratio = item.ratio {
                    cellView?.textField?.stringValue = String(format: "%.0f%%", ratio * 100)
                } else {
                    cellView?.textField?.stringValue = "—"
                }
                cellView?.textField?.alignment = .right

            case "Modified":
                cellView?.textField?.stringValue = item.dateModified.map { archiveModifiedDateFormatter.string(from: $0) } ?? ""
                cellView?.textField?.alignment = .right

            default:
                cellView?.textField?.stringValue = ""
            }

            return cellView
        }

        private func formattedByteCount(_ bytes: Int64) -> String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return formatter.string(fromByteCount: bytes)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView, let dataSource else { return }
            var newSelection: Set<String> = []
            for index in tableView.selectedRowIndexes where index < dataSource.items.count {
                newSelection.insert(dataSource.items[index].path)
            }
            selectedItems = newSelection
        }

        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let columnId = tableColumn.identifier.rawValue
            guard let newSortColumn = ArchiveSortColumn.allCases.first(where: { $0.rawValue == columnId }) else { return }

            if sortColumn == newSortColumn {
                sortAscending.toggle()
            } else {
                sortColumn = newSortColumn
                sortAscending = true
            }
        }

        func tableView(_ tableView: NSTableView, shouldEdit row: Int) -> Bool {
            false
        }

        @objc func handleDoubleClick(_ sender: NSTableView) {
            guard let dataSource, sender.clickedRow >= 0, sender.clickedRow < dataSource.items.count else { return }
            onDoubleClick?(dataSource.items[sender.clickedRow])
        }
    }
}

final class ArchiveContentsDataSource: NSObject, NSTableViewDataSource {
    var items: [ArchiveItem]

    init(items: [ArchiveItem]) {
        self.items = items
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }
}

/// A scroll view that also accepts file drops onto the table beneath it — dragging files in
/// from Finder is still a valid way to add them to the archive in Power mode.
final class DropAcceptingScrollView: NSScrollView {
    var onDropFiles: (([URL]) -> Void)?

    init(scrollView: NSScrollView) {
        super.init(frame: .zero)
        // Copy properties from the original scroll view
        self.hasVerticalScroller = scrollView.hasVerticalScroller
        self.hasHorizontalScroller = scrollView.hasHorizontalScroller
        self.autohidesScrollers = scrollView.autohidesScrollers
        self.borderType = scrollView.borderType
        // Transfer the document view (table view) to this scroll view
        if let documentView = scrollView.documentView {
            self.documentView = documentView
        }

        self.registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard

        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !urls.isEmpty else {
            return false
        }

        // Filter out directories - only allow files
        let fileURLs = urls.filter { url in
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return !isDirectory.boolValue
        }

        if !fileURLs.isEmpty {
            onDropFiles?(fileURLs)
        }

        return !fileURLs.isEmpty
    }
}
