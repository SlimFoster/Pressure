import SwiftUI
import AppKit

struct FileSystemNavigator: View {
    @Binding var selectedFiles: [URL]
    
    var body: some View {
        FinderStyleNavigator(selectedFiles: $selectedFiles)
    }
}

struct OutlineViewWrapper: NSViewRepresentable {
    @Binding var selectedFiles: [URL]
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let outlineView = NSOutlineView()
        
        // Configure scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.documentView = outlineView
        
        // Configure outline view
        outlineView.headerView = nil
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.allowsMultipleSelection = true
        outlineView.selectionHighlightStyle = .regular
        outlineView.autoresizesOutlineColumn = true
        outlineView.rowHeight = 20
        outlineView.intercellSpacing = NSSize(width: 4, height: 2)
        outlineView.indentationPerLevel = 16
        outlineView.indentationMarkerFollowsCell = false
        
        // Ensure proper disclosure triangle rendering
        outlineView.floatsGroupRows = false
        
        // Create column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("FileColumn"))
        column.title = "Files"
        column.minWidth = 200
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        
        // Set data source and delegate
        let dataSource = FileSystemDataSource()
        context.coordinator.dataSource = dataSource
        context.coordinator.outlineView = outlineView
        outlineView.dataSource = dataSource
        outlineView.delegate = context.coordinator
        
        // Enable dragging
        outlineView.setDraggingSourceOperationMask([.copy], forLocal: true)
        outlineView.setDraggingSourceOperationMask([.copy], forLocal: false)
        
        // Set root item
        dataSource.rootURL = FileManager.default.homeDirectoryForCurrentUser
        outlineView.reloadData()
        
        // Expand root
        DispatchQueue.main.async {
            outlineView.expandItem(dataSource.rootURL)
        }
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Update if needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(selectedFiles: $selectedFiles)
    }
    
    class Coordinator: NSObject, NSOutlineViewDelegate {
        @Binding var selectedFiles: [URL]
        var dataSource: FileSystemDataSource?
        weak var outlineView: NSOutlineView?
        
        init(selectedFiles: Binding<[URL]>) {
            self._selectedFiles = selectedFiles
        }
        
        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let url = item as? URL else { return nil }
            
            let identifier = NSUserInterfaceItemIdentifier("FileCell")
            var cellView = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView
            
            if cellView == nil {
                cellView = NSTableCellView()
                cellView!.identifier = identifier
                
                // Create image view for file icon
                let imageView = NSImageView()
                imageView.translatesAutoresizingMaskIntoConstraints = false
                imageView.imageScaling = .scaleProportionallyDown
                imageView.imageAlignment = .alignCenter
                cellView!.addSubview(imageView)
                
                // Create text field for file name
                let textField = NSTextField()
                textField.translatesAutoresizingMaskIntoConstraints = false
                textField.isEditable = false
                textField.isBordered = false
                textField.drawsBackground = false
                textField.lineBreakMode = .byTruncatingMiddle
                cellView!.textField = textField
                cellView!.addSubview(textField)
                
                // Layout constraints
                // NSOutlineView automatically handles disclosure triangle and indentation
                // From UI inspection: disclosure button is at x=196, width=15 (ends at x=211)
                // Icon should start AFTER disclosure area. Disclosure is ~15-16 points wide.
                // We position icon to start after disclosure triangle (typically 16-18 points from leading)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: cellView!.leadingAnchor, constant: 18),
                    imageView.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor),
                    imageView.widthAnchor.constraint(equalToConstant: 16),
                    imageView.heightAnchor.constraint(equalToConstant: 16),
                    textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 6),
                    textField.trailingAnchor.constraint(equalTo: cellView!.trailingAnchor, constant: -4),
                    textField.centerYAnchor.constraint(equalTo: cellView!.centerYAnchor)
                ])
            }
            
            // Update icon
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            
            // Find the image view (it's the first NSImageView that's not the textField)
            if let imageView = cellView?.subviews.first(where: { $0 is NSImageView && $0 !== cellView?.textField }) as? NSImageView {
                imageView.image = icon
            }
            
            // Update text
            cellView?.textField?.stringValue = url.lastPathComponent
            
            return cellView
        }
        
        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            guard let url = item as? URL else { return false }
            return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        }
        
        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            
            let selectedIndexes = outlineView.selectedRowIndexes
            var newSelection: [URL] = []
            
            for index in selectedIndexes {
                if let url = outlineView.item(atRow: index) as? URL {
                    // Only add files, not directories
                    let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if !isDirectory {
                        newSelection.append(url)
                    }
                }
            }
            
            selectedFiles = newSelection
        }
        
        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            // Allow selection of both files and directories
            // Directories can be expanded/collapsed, files can be selected
            return true
        }
    }
}

class FileSystemDataSource: NSObject, NSOutlineViewDataSource {
    var rootURL: URL = FileManager.default.homeDirectoryForCurrentUser
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        let url: URL
        if let itemURL = item as? URL {
            url = itemURL
        } else {
            url = rootURL
        }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }
        
        return contents.count
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        let url: URL
        if let itemURL = item as? URL {
            url = itemURL
        } else {
            url = rootURL
        }
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return url
        }
        
        // Sort: directories first, then by name
        let sorted = contents.sorted { first, second in
            let firstIsDir = (try? first.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let secondIsDir = (try? second.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            
            if firstIsDir != secondIsDir {
                return firstIsDir
            }
            return first.lastPathComponent < second.lastPathComponent
        }
        
        guard index < sorted.count else {
            return url
        }
        
        return sorted[index]
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let url = item as? URL else { return false }
        return (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
    }
    
    // MARK: - Drag Support
    
    func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let url = item as? URL else { return nil }
        
        // Only allow dragging files, not directories
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        if isDirectory {
            return nil
        }
        
        return url as NSPasteboardWriting
    }
    
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItems draggedItems: [Any]) {
        // Optional: customize drag appearance
    }
    
    func outlineView(_ outlineView: NSOutlineView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        // Optional: handle drag end
    }
}
