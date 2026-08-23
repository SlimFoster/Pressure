import SwiftUI
import AppKit

/// A row in the Power-mode sidebar. Modeled as an ordered list of sections so a "Recents"
/// section can be added above the archive tree later without restructuring — for now only
/// the archive-tree section is populated.
final class SidebarNode: NSObject {
    enum Kind {
        case header
        case allFiles
        case folder
    }

    let kind: Kind
    let title: String
    let path: String
    var itemCount: Int
    var children: [SidebarNode]

    init(kind: Kind, title: String, path: String = "", itemCount: Int = 0, children: [SidebarNode] = []) {
        self.kind = kind
        self.title = title
        self.path = path
        self.itemCount = itemCount
        self.children = children
    }
}

struct ArchiveSidebarView: NSViewRepresentable {
    var archiveName: String
    var items: [ArchiveItem]
    @Binding var selectedPath: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = outlineView

        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = false
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.allowsMultipleSelection = false
        outlineView.selectionHighlightStyle = .regular
        outlineView.autoresizesOutlineColumn = true
        outlineView.rowHeight = 22
        outlineView.indentationPerLevel = 14
        outlineView.floatsGroupRows = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.title = "Archive"
        column.minWidth = 160
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        let dataSource = SidebarDataSource()
        context.coordinator.dataSource = dataSource
        context.coordinator.outlineView = outlineView
        outlineView.dataSource = dataSource
        outlineView.delegate = context.coordinator

        outlineView.reloadData()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let outlineView = nsView.documentView as? NSOutlineView,
              let dataSource = context.coordinator.dataSource else {
            return
        }

        context.coordinator.selectedPath = $selectedPath

        let previouslyExpandedPaths = context.coordinator.expandedPaths(in: outlineView, dataSource: dataSource)

        dataSource.root = Self.buildTree(archiveName: archiveName, items: items)
        outlineView.reloadData()

        context.coordinator.expand(pathsMatching: previouslyExpandedPaths, in: outlineView, dataSource: dataSource)
        context.coordinator.selectRow(for: selectedPath, in: outlineView, dataSource: dataSource)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedPath: $selectedPath)
    }

    /// Builds the sidebar's row hierarchy: a non-selectable header row naming the archive, an
    /// "All Files" row for the archive root, then the folder tree as siblings of "All Files".
    static func buildTree(archiveName: String, items: [ArchiveItem]) -> SidebarNode {
        let root = SidebarNode(kind: .header, title: "") // container only; never rendered itself
        let header = SidebarNode(kind: .header, title: archiveName.uppercased())
        let allFiles = SidebarNode(kind: .allFiles, title: "All Files", path: "")

        let directories = items.filter { $0.isDirectory }
        var nodesByPath: [String: SidebarNode] = [:]
        for dir in directories.sorted(by: { $0.path.count < $1.path.count }) {
            nodesByPath[dir.path] = SidebarNode(kind: .folder, title: dir.name, path: dir.path)
        }

        var topLevel: [SidebarNode] = []
        for dir in directories {
            guard let node = nodesByPath[dir.path] else { continue }
            let parentPath = (dir.path as NSString).deletingLastPathComponent
            if !parentPath.isEmpty, let parent = nodesByPath[parentPath] {
                parent.children.append(node)
            } else {
                topLevel.append(node)
            }
        }

        for (path, node) in nodesByPath {
            node.itemCount = items.filter { item in
                (item.path as NSString).deletingLastPathComponent == path
            }.count
        }

        func sortedRecursively(_ nodes: [SidebarNode]) -> [SidebarNode] {
            nodes.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                .map { node in
                    node.children = sortedRecursively(node.children)
                    return node
                }
        }

        root.children = [header, allFiles] + sortedRecursively(topLevel)
        return root
    }

    final class Coordinator: NSObject, NSOutlineViewDelegate {
        var selectedPath: Binding<String>
        var dataSource: SidebarDataSource?
        weak var outlineView: NSOutlineView?
        private var isUpdatingSelectionProgrammatically = false

        init(selectedPath: Binding<String>) {
            self.selectedPath = selectedPath
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? SidebarNode else { return nil }

            if node.kind == .header {
                let identifier = NSUserInterfaceItemIdentifier("HeaderCell")
                let cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                    ?? makeHeaderCell(identifier: identifier)
                cellView.textField?.stringValue = node.title
                return cellView
            }

            let identifier = NSUserInterfaceItemIdentifier("RowCell")
            let cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
                ?? makeRowCell(identifier: identifier)

            let imageView = cellView.subviews.first { $0 is NSImageView } as? NSImageView
            imageView?.image = NSImage(
                systemSymbolName: node.kind == .allFiles ? "tray.full" : "folder.fill",
                accessibilityDescription: nil
            )
            cellView.textField?.stringValue = node.title

            let badge = cellView.subviews.first { $0 is BadgeView } as? BadgeView
            if node.kind == .folder {
                badge?.isHidden = false
                badge?.countLabel?.stringValue = "\(node.itemCount)"
            } else {
                badge?.isHidden = true
            }

            return cellView
        }

        private func makeHeaderCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cellView = NSTableCellView()
            cellView.identifier = identifier

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.font = .systemFont(ofSize: 10, weight: .semibold)
            textField.textColor = .secondaryLabelColor
            cellView.textField = textField
            cellView.addSubview(textField)

            NSLayoutConstraint.activate([
                textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 4),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: cellView.trailingAnchor, constant: -4),
                textField.bottomAnchor.constraint(equalTo: cellView.bottomAnchor, constant: -2)
            ])

            return cellView
        }

        private func makeRowCell(identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
            let cellView = NSTableCellView()
            cellView.identifier = identifier

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown
            imageView.contentTintColor = .secondaryLabelColor
            cellView.addSubview(imageView)

            let textField = NSTextField(labelWithString: "")
            textField.translatesAutoresizingMaskIntoConstraints = false
            textField.lineBreakMode = .byTruncatingTail
            cellView.textField = textField
            cellView.addSubview(textField)

            let badge = badgeView()
            cellView.addSubview(badge)

            NSLayoutConstraint.activate([
                imageView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
                imageView.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 15),
                imageView.heightAnchor.constraint(equalToConstant: 15),

                textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 5),
                textField.trailingAnchor.constraint(lessThanOrEqualTo: badge.leadingAnchor, constant: -6),
                textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),

                badge.trailingAnchor.constraint(equalTo: cellView.trailingAnchor, constant: -4),
                badge.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
            ])

            return cellView
        }

        private func badgeView() -> NSView {
            let container = BadgeView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let label = NSTextField(labelWithString: "0")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.font = .systemFont(ofSize: 10, weight: .medium)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            container.addSubview(label)
            container.countLabel = label

            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                label.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
                label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -1),
                container.heightAnchor.constraint(equalToConstant: 16)
            ])

            return container
        }

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            (item as? SidebarNode)?.kind == .header
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            (item as? SidebarNode)?.kind != .header
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let node = item as? SidebarNode else { return false }
            return !node.children.isEmpty
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdatingSelectionProgrammatically,
                  let outlineView = notification.object as? NSOutlineView,
                  let node = outlineView.item(atRow: outlineView.selectedRow) as? SidebarNode,
                  node.kind != .header else {
                return
            }
            selectedPath.wrappedValue = node.path
        }

        func expandedPaths(in outlineView: NSOutlineView, dataSource: SidebarDataSource) -> Set<String> {
            var expanded: Set<String> = []
            func walk(_ node: SidebarNode) {
                if outlineView.isItemExpanded(node) {
                    expanded.insert(node.path)
                }
                node.children.forEach(walk)
            }
            dataSource.root.children.forEach(walk)
            return expanded
        }

        func expand(pathsMatching expanded: Set<String>, in outlineView: NSOutlineView, dataSource: SidebarDataSource) {
            func walk(_ node: SidebarNode) {
                // First level always visible; auto-expand folders that were expanded before,
                // plus expand everything on first load (empty `expanded` set) for discoverability.
                if expanded.isEmpty || expanded.contains(node.path) {
                    outlineView.expandItem(node)
                }
                node.children.forEach(walk)
            }
            dataSource.root.children.forEach(walk)
        }

        func selectRow(for path: String, in outlineView: NSOutlineView, dataSource: SidebarDataSource) {
            func find(_ node: SidebarNode) -> SidebarNode? {
                if node.kind != .header && node.path == path { return node }
                for child in node.children {
                    if let match = find(child) { return match }
                }
                return nil
            }
            guard let target = find(dataSource.root) ?? dataSource.root.children.first(where: { $0.kind == .allFiles }) else {
                return
            }
            let row = outlineView.row(forItem: target)
            guard row >= 0, outlineView.selectedRow != row else { return }

            isUpdatingSelectionProgrammatically = true
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            isUpdatingSelectionProgrammatically = false
        }
    }
}

final class SidebarDataSource: NSObject, NSOutlineViewDataSource {
    var root = SidebarNode(kind: .header, title: "")

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        ((item as? SidebarNode) ?? root).children.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        ((item as? SidebarNode) ?? root).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        !((item as? SidebarNode)?.children.isEmpty ?? true)
    }
}

/// Small pill background for the sidebar's per-folder item-count badge.
final class BadgeView: NSView {
    weak var countLabel: NSTextField?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
    }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        layer?.cornerRadius = 8
    }
}
