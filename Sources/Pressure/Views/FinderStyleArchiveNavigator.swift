import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FinderStyleArchiveNavigator: View {
    @ObservedObject var archiveModel: ArchiveModel
    @Binding var selectedArchiveItems: Set<String>
    @State private var searchText: String = ""
    @State private var sortColumn: ArchiveSortColumn = .name
    @State private var sortAscending: Bool = true
    @State private var viewMode: ViewMode = .list
    @State private var navigationHistory: [String] = []
    @State private var historyIndex: Int = -1
    
    enum ArchiveSortColumn: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case kind = "Kind"
        case dateModified = "Date Modified"
    }
    
    enum ViewMode {
        case list, grid, column, gallery
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Finder-style toolbar
            ArchiveFinderToolbar(
                currentPath: archiveModel.currentPath.isEmpty ? "Archive" : archiveModel.currentPath,
                searchText: $searchText,
                viewMode: $viewMode,
                canGoBack: canGoUp,
                canGoForward: canGoForward,
                onBack: navigateUp,
                onForward: goForward,
                onCreateDirectory: { archiveModel.createDirectory() },
                onAddFiles: {
                    Task {
                        await openFilePicker()
                    }
                }
            )
            
            // Table view with columns
            ArchiveTableViewWrapper(
                items: filteredAndSortedItems,
                selectedItems: $selectedArchiveItems,
                sortColumn: $sortColumn,
                sortAscending: $sortAscending,
                onDoubleClick: { item in
                    if item.isDirectory {
                        archiveModel.navigateToPath(item.path)
                    }
                },
                onDropFiles: { urls in
                    for url in urls {
                        archiveModel.addFileToArchive(url, at: archiveModel.currentPath)
                    }
                }
            )
        }
        .onChange(of: archiveModel.currentPath) { _ in
            updateNavigationHistory()
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            return handleDrop(providers: providers)
        }
    }
    
    private var filteredAndSortedItems: [ArchiveItem] {
        var items = archiveModel.currentItems
        
        // Apply search filter
        if !searchText.isEmpty {
            items = items.filter { item in
                item.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Apply sorting
        items.sort { first, second in
            let ascending = sortAscending
            switch sortColumn {
            case .name:
                return ascending ? first.name < second.name : first.name > second.name
            case .size:
                let firstSize = first.size ?? 0
                let secondSize = second.size ?? 0
                return ascending ? firstSize < secondSize : firstSize > secondSize
            case .kind:
                let firstKind = first.isDirectory ? "Folder" : "Document"
                let secondKind = second.isDirectory ? "Folder" : "Document"
                return ascending ? firstKind < secondKind : firstKind > secondKind
            case .dateModified:
                // Archive items don't have dates, so sort by name as fallback
                return ascending ? first.name < second.name : first.name > second.name
            }
        }
        
        // Directories first
        return items.sorted { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory
            }
            return false // Already sorted above
        }
    }
    
    private var canGoUp: Bool {
        !archiveModel.currentPath.isEmpty
    }
    
    private var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }
    
    private func navigateUp() {
        guard canGoUp else { return }
        archiveModel.navigateUp()
    }
    
    private func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        archiveModel.navigateToPath(navigationHistory[historyIndex])
    }
    
    private func updateNavigationHistory() {
        let currentPath = archiveModel.currentPath
        if navigationHistory.isEmpty || (historyIndex >= 0 && historyIndex < navigationHistory.count && navigationHistory[historyIndex] != currentPath) {
            // Remove any forward history
            if historyIndex < navigationHistory.count - 1 {
                navigationHistory.removeSubrange((historyIndex + 1)...)
            }
            navigationHistory.append(currentPath)
            historyIndex = navigationHistory.count - 1
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var hasValidFiles = false
        
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                hasValidFiles = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        return
                    }
                    
                    Task { @MainActor in
                        archiveModel.addFileToArchive(url, at: archiveModel.currentPath)
                    }
                }
            }
        }
        
        return hasValidFiles
    }
    
    private func openFilePicker() async {
        guard let fileURLs = await NSOpenPanel.showOpenPanel(
            canChooseFiles: true,
            canChooseDirectories: false,
            allowsMultipleSelection: true,
            allowedContentTypes: [UTType.item.identifier]
        ) else {
            return
        }
        
        await MainActor.run {
            for url in fileURLs {
                archiveModel.addFileToArchive(url, at: archiveModel.currentPath)
            }
        }
    }
}

struct ArchiveFinderToolbar: View {
    let currentPath: String
    @Binding var searchText: String
    @Binding var viewMode: FinderStyleArchiveNavigator.ViewMode
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    let onCreateDirectory: () -> Void
    let onAddFiles: () -> Void
    
    var body: some View {
        HStack(spacing: 8) {
            // Navigation buttons
            HStack(spacing: 0) {
                Button(action: onBack) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoBack)
                .frame(width: 28, height: 22)
                
                Button(action: onForward) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(!canGoForward)
                .frame(width: 28, height: 22)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
            
            // Current path
            Text(currentPath.isEmpty ? "Archive" : currentPath)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
            
            Spacer()
            
            // Action buttons
            Button(action: onCreateDirectory) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 22)
            
            Button(action: onAddFiles) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .frame(width: 24, height: 22)
            
            // View mode buttons
            HStack(spacing: 0) {
                ArchiveViewModeButton(icon: "square.grid.2x2", mode: .grid, selectedMode: $viewMode)
                ArchiveViewModeButton(icon: "list.bullet", mode: .list, selectedMode: $viewMode)
                ArchiveViewModeButton(icon: "rectangle.split.3x1", mode: .column, selectedMode: $viewMode)
                ArchiveViewModeButton(icon: "photo.on.rectangle", mode: .gallery, selectedMode: $viewMode)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
            
            Spacer()
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 200)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct ArchiveViewModeButton: View {
    let icon: String
    let mode: FinderStyleArchiveNavigator.ViewMode
    @Binding var selectedMode: FinderStyleArchiveNavigator.ViewMode
    
    var body: some View {
        Button(action: { selectedMode = mode }) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(selectedMode == mode ? .primary : .secondary)
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.plain)
        .background(selectedMode == mode ? Color(NSColor.selectedControlColor).opacity(0.3) : Color.clear)
    }
}

struct ArchiveTableViewWrapper: NSViewRepresentable {
    let items: [ArchiveItem]
    @Binding var selectedItems: Set<String>
    @Binding var sortColumn: FinderStyleArchiveNavigator.ArchiveSortColumn
    @Binding var sortAscending: Bool
    let onDoubleClick: (ArchiveItem) -> Void
    let onDropFiles: ([URL]) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = tableView
        
        // Configure table view
        tableView.headerView = NSTableHeaderView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsMultipleSelection = true
        tableView.selectionHighlightStyle = .regular
        tableView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        tableView.rowHeight = 20
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        
        // Create columns (matching Finder style)
        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Name"))
        nameColumn.title = "Name"
        nameColumn.minWidth = 150
        nameColumn.width = 250
        nameColumn.resizingMask = [.autoresizingMask, .userResizingMask]
        tableView.addTableColumn(nameColumn)
        
        let sizeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Size"))
        sizeColumn.title = "Size"
        sizeColumn.minWidth = 80
        sizeColumn.width = 100
        sizeColumn.headerCell.alignment = .right
        tableView.addTableColumn(sizeColumn)
        
        let kindColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Kind"))
        kindColumn.title = "Kind"
        kindColumn.minWidth = 120
        kindColumn.width = 150
        tableView.addTableColumn(kindColumn)
        
        let dateColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Date Modified"))
        dateColumn.title = "Date Modified"
        dateColumn.minWidth = 150
        dateColumn.width = 200
        dateColumn.headerCell.alignment = .right
        tableView.addTableColumn(dateColumn)
        
        // Set data source and delegate
        let dataSource = ArchiveTableViewDataSource(items: items)
        context.coordinator.dataSource = dataSource
        context.coordinator.tableView = tableView
        context.coordinator.onDoubleClick = onDoubleClick
        tableView.dataSource = dataSource
        tableView.delegate = context.coordinator
        
        // Create a custom scroll view that handles drops
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
    
    class Coordinator: NSObject, NSTableViewDelegate {
        @Binding var selectedItems: Set<String>
        @Binding var sortColumn: FinderStyleArchiveNavigator.ArchiveSortColumn
        @Binding var sortAscending: Bool
        var dataSource: ArchiveTableViewDataSource?
        weak var tableView: NSTableView?
        var onDoubleClick: ((ArchiveItem) -> Void)?
        
        init(selectedItems: Binding<Set<String>>, sortColumn: Binding<FinderStyleArchiveNavigator.ArchiveSortColumn>, sortAscending: Binding<Bool>) {
            self._selectedItems = selectedItems
            self._sortColumn = sortColumn
            self._sortAscending = sortAscending
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let dataSource = dataSource,
                  row < dataSource.items.count else {
                return nil
            }
            
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
                
                // For Name column, we'll add icon separately
                if columnId == "Name" {
                    let imageView = NSImageView()
                    imageView.translatesAutoresizingMaskIntoConstraints = false
                    imageView.imageScaling = .scaleProportionallyDown
                    imageView.imageAlignment = .alignCenter
                    cellView?.addSubview(imageView)
                    
                    NSLayoutConstraint.activate([
                        imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 4),
                        imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                        imageView.widthAnchor.constraint(equalToConstant: 16),
                        imageView.heightAnchor.constraint(equalToConstant: 16),
                        textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                        textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
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
            
            // Set content based on column
            switch columnId {
            case "Name":
                let iconName = item.isDirectory ? "folder.fill" : "doc"
                let icon = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
                icon?.size = NSSize(width: 16, height: 16)
                if let imageView = cellView?.subviews.first(where: { $0 is NSImageView }) as? NSImageView {
                    imageView.image = icon
                }
                cellView?.textField?.stringValue = item.name
                
            case "Size":
                if let size = item.size {
                    let formatter = ByteCountFormatter()
                    formatter.countStyle = .file
                    cellView?.textField?.stringValue = formatter.string(fromByteCount: size)
                } else {
                    cellView?.textField?.stringValue = item.isDirectory ? "—" : ""
                }
                cellView?.textField?.alignment = .right
                
            case "Kind":
                cellView?.textField?.stringValue = item.isDirectory ? "Folder" : "Document"
                
            case "Date Modified":
                cellView?.textField?.stringValue = "" // Archives don't have modification dates
                cellView?.textField?.alignment = .right
                
            default:
                cellView?.textField?.stringValue = ""
            }
            
            return cellView
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let selectedIndexes = tableView.selectedRowIndexes
            var newSelection: Set<String> = []
            
            for index in selectedIndexes {
                if let dataSource = dataSource,
                   index < dataSource.items.count {
                    newSelection.insert(dataSource.items[index].path)
                }
            }
            
            selectedItems = newSelection
        }
        
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let columnId = tableColumn.identifier.rawValue
            
            if let newSortColumn = FinderStyleArchiveNavigator.ArchiveSortColumn.allCases.first(where: { $0.rawValue == columnId }) {
                if sortColumn == newSortColumn {
                    sortAscending.toggle()
                } else {
                    sortColumn = newSortColumn
                    sortAscending = true
                }
            }
        }
        
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return true
        }
        
        func tableView(_ tableView: NSTableView, shouldEdit row: Int) -> Bool {
            return false
        }
        
        func tableView(_ tableView: NSTableView, didDoubleClick row: Int) {
            guard let dataSource = dataSource,
                  row < dataSource.items.count else {
                return
            }
            
            let item = dataSource.items[row]
            onDoubleClick?(item)
        }
    }
}

// Custom scroll view that accepts file drops
class DropAcceptingScrollView: NSScrollView {
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
        
        // Register for drag and drop
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

class ArchiveTableViewDataSource: NSObject, NSTableViewDataSource {
    var items: [ArchiveItem]
    
    init(items: [ArchiveItem]) {
        self.items = items
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}
