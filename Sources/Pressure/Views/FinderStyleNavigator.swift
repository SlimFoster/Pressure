import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct FinderStyleNavigator: View {
    @Binding var selectedFiles: [URL]
    @State private var currentDirectory: URL
    @State private var fileItems: [FileItem] = []
    @State private var searchText: String = ""
    @State private var sortColumn: SortColumn = .name
    @State private var sortAscending: Bool = true
    @State private var viewMode: ViewMode = .list
    @State private var navigationHistory: [URL] = []
    @State private var historyIndex: Int = -1
    
    enum SortColumn: String, CaseIterable {
        case name = "Name"
        case size = "Size"
        case kind = "Kind"
        case dateModified = "Date Modified"
    }
    
    enum ViewMode {
        case list, grid, column, gallery
    }
    
    init(selectedFiles: Binding<[URL]>, initialDirectory: URL? = nil) {
        self._selectedFiles = selectedFiles
        _currentDirectory = State(initialValue: initialDirectory ?? FileManager.default.homeDirectoryForCurrentUser)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Finder-style toolbar
            FinderToolbar(
                currentDirectory: currentDirectory,
                searchText: $searchText,
                viewMode: $viewMode,
                canGoBack: canGoUp,
                canGoForward: canGoForward,
                onBack: navigateUp,
                onForward: goForward
            )
            
            // Table view with columns
            TableViewWrapper(
                items: filteredAndSortedItems,
                selectedFiles: $selectedFiles,
                sortColumn: $sortColumn,
                sortAscending: $sortAscending,
                onDoubleClick: { url in
                    navigateToFolder(url)
                }
            )
        }
        .onAppear {
            loadDirectory()
        }
        .onChange(of: currentDirectory) { _ in
            loadDirectory()
        }
        .onChange(of: searchText) { _ in
            // Filtering happens in computed property
        }
    }
    
    private var filteredAndSortedItems: [FileItem] {
        var items = fileItems
        
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
                let firstKind = first.kind
                let secondKind = second.kind
                return ascending ? firstKind < secondKind : firstKind > secondKind
            case .dateModified:
                let firstDate = first.dateModified ?? Date.distantPast
                let secondDate = second.dateModified ?? Date.distantPast
                return ascending ? firstDate < secondDate : firstDate > secondDate
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
        currentDirectory.path != "/" && currentDirectory.pathComponents.count > 1
    }
    
    private var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }
    
    private func navigateUp() {
        guard canGoUp else { return }
        let parentDirectory = currentDirectory.deletingLastPathComponent()
        currentDirectory = parentDirectory
    }
    
    private func goForward() {
        guard canGoForward else { return }
        historyIndex += 1
        currentDirectory = navigationHistory[historyIndex]
    }
    
    private func navigateToFolder(_ url: URL) {
        currentDirectory = url
    }
    
    private func loadDirectory() {
        fileItems = []
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: currentDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        
        fileItems = contents.map { url in
            let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey, .contentModificationDateKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            let size = resourceValues?.fileSize.map(Int64.init)
            let contentType = resourceValues?.contentType
            let dateModified = resourceValues?.contentModificationDate
            
            return FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                size: size,
                kind: contentType?.localizedDescription ?? (isDirectory ? "Folder" : "Document"),
                dateModified: dateModified
            )
        }
        
        // Add to navigation history
        if navigationHistory.isEmpty || navigationHistory[historyIndex] != currentDirectory {
            // Remove any forward history
            if historyIndex < navigationHistory.count - 1 {
                navigationHistory.removeSubrange((historyIndex + 1)...)
            }
            navigationHistory.append(currentDirectory)
            historyIndex = navigationHistory.count - 1
        }
    }
}

struct FileItem {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let kind: String
    let dateModified: Date?
}

struct FinderToolbar: View {
    let currentDirectory: URL
    @Binding var searchText: String
    @Binding var viewMode: FinderStyleNavigator.ViewMode
    let canGoBack: Bool
    let canGoForward: Bool
    let onBack: () -> Void
    let onForward: () -> Void
    
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
            
            // Current directory name
            Text(currentDirectory.lastPathComponent)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: 200, alignment: .leading)
            
            Spacer()
            
            // View mode buttons
            HStack(spacing: 0) {
                ViewModeButton(icon: "square.grid.2x2", mode: .grid, selectedMode: $viewMode)
                ViewModeButton(icon: "list.bullet", mode: .list, selectedMode: $viewMode)
                ViewModeButton(icon: "rectangle.split.3x1", mode: .column, selectedMode: $viewMode)
                ViewModeButton(icon: "photo.on.rectangle", mode: .gallery, selectedMode: $viewMode)
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

struct ViewModeButton: View {
    let icon: String
    let mode: FinderStyleNavigator.ViewMode
    @Binding var selectedMode: FinderStyleNavigator.ViewMode
    
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

struct TableViewWrapper: NSViewRepresentable {
    let items: [FileItem]
    @Binding var selectedFiles: [URL]
    @Binding var sortColumn: FinderStyleNavigator.SortColumn
    @Binding var sortAscending: Bool
    let onDoubleClick: (URL) -> Void
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = DraggableTableView()
        
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
        
        // Create columns
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
        let dataSource = TableViewDataSource(items: items)
        context.coordinator.dataSource = dataSource
        context.coordinator.tableView = tableView
        tableView.dataSource = dataSource
        tableView.delegate = context.coordinator
        
        // Enable dragging - set operation mask for both local and external drags
        tableView.setDraggingSourceOperationMask([.copy], forLocal: false)
        tableView.setDraggingSourceOperationMask([.copy], forLocal: true)
        
        // Add double-click handler
        let doubleClickTarget = context.coordinator
        tableView.target = doubleClickTarget
        tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tableView = nsView.documentView as? NSTableView,
              let dataSource = context.coordinator.dataSource else {
            return
        }
        
        dataSource.items = items
        tableView.reloadData()
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedFiles: $selectedFiles, sortColumn: $sortColumn, sortAscending: $sortAscending, onDoubleClick: onDoubleClick)
    }
    
    class Coordinator: NSObject, NSTableViewDelegate {
        @Binding var selectedFiles: [URL]
        @Binding var sortColumn: FinderStyleNavigator.SortColumn
        @Binding var sortAscending: Bool
        var dataSource: TableViewDataSource?
        weak var tableView: NSTableView?
        let onDoubleClick: (URL) -> Void
        
        init(selectedFiles: Binding<[URL]>, sortColumn: Binding<FinderStyleNavigator.SortColumn>, sortAscending: Binding<Bool>, onDoubleClick: @escaping (URL) -> Void) {
            self._selectedFiles = selectedFiles
            self._sortColumn = sortColumn
            self._sortAscending = sortAscending
            self.onDoubleClick = onDoubleClick
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
                let icon = NSWorkspace.shared.icon(forFile: item.url.path)
                icon.size = NSSize(width: 16, height: 16)
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
                cellView?.textField?.stringValue = item.kind
                
            case "Date Modified":
                if let date = item.dateModified {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .short
                    cellView?.textField?.stringValue = formatter.string(from: date)
                } else {
                    cellView?.textField?.stringValue = ""
                }
                cellView?.textField?.alignment = .right
                
            default:
                cellView?.textField?.stringValue = ""
            }
            
            return cellView
        }
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let selectedIndexes = tableView.selectedRowIndexes
            var newSelection: [URL] = []
            
            for index in selectedIndexes {
                if let dataSource = dataSource,
                   index < dataSource.items.count {
                    let item = dataSource.items[index]
                    if !item.isDirectory {
                        newSelection.append(item.url)
                    }
                }
            }
            
            selectedFiles = newSelection
        }
        
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            let columnId = tableColumn.identifier.rawValue
            
            if let newSortColumn = FinderStyleNavigator.SortColumn.allCases.first(where: { $0.rawValue == columnId }) {
                if sortColumn == newSortColumn {
                    sortAscending.toggle()
                } else {
                    sortColumn = newSortColumn
                    sortAscending = true
                }
            }
        }
        
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard let dataSource = dataSource,
                  row < dataSource.items.count else {
                print("pasteboardWriterForRow: Invalid row \(row)")
                return nil
            }
            
            let item = dataSource.items[row]
            if item.isDirectory {
                print("pasteboardWriterForRow: Skipping directory \(item.name)")
                return nil
            }
            
            print("pasteboardWriterForRow: Providing URL for \(item.name)")
            // Return the URL as a pasteboard writer
            return item.url as NSPasteboardWriting
        }
        
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) {
            // Optional: Customize drag appearance
            // This is called when the drag session begins
            print("Drag session starting for rows: \(rowIndexes)")
        }
        
        func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            // Optional: Handle drag end
        }
        
        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
            return true
        }
        
        @objc func handleDoubleClick(_ sender: Any) {
            guard let tableView = sender as? NSTableView else { return }
            let clickedRow = tableView.clickedRow
            
            guard clickedRow >= 0,
                  let dataSource = dataSource,
                  clickedRow < dataSource.items.count else {
                return
            }
            
            let item = dataSource.items[clickedRow]
            if item.isDirectory {
                onDoubleClick(item.url)
            }
        }
    }
}

class TableViewDataSource: NSObject, NSTableViewDataSource {
    var items: [FileItem]
    
    init(items: [FileItem]) {
        self.items = items
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count
    }
}

// Custom table view that ensures dragging works properly
// NSTableView automatically handles drag operations when pasteboardWriterForRow is implemented
// We just need to ensure it's a proper NSTableView subclass
class DraggableTableView: NSTableView {
    // NSTableView will automatically call pasteboardWriterForRow when dragging starts
    // No need to override mouse methods - let NSTableView handle it natively
}
