import SwiftUI
import UniformTypeIdentifiers

struct ArchiveNavigator: View {
    @ObservedObject var archiveModel: ArchiveModel
    @Binding var selectedArchiveItems: Set<String>
    
    var body: some View {
        FinderStyleArchiveNavigator(
            archiveModel: archiveModel,
            selectedArchiveItems: $selectedArchiveItems
        )
    }
}

struct ArchiveItem {
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64?
}

struct ArchiveRow: View {
    let item: ArchiveItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc")
                .foregroundColor(item.isDirectory ? .blue : .secondary)
            
            Text(item.name)
                .lineLimit(1)
            
            Spacer()
            
            if let size = item.size, !item.isDirectory {
                Text(formatSize(size))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 1, perform: onSelect)
        .onTapGesture(count: 2, perform: onDoubleClick)
        .background(isSelected ? Color.blue.opacity(0.2) : Color.clear)
    }
    
    private func formatSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct ArchiveFile {
    let archivePath: String
    let sourceURL: URL
    let isDirectory: Bool
}

@MainActor
class ArchiveModel: ObservableObject {
    @Published var items: [ArchiveItem] = []
    @Published var currentPath: String = ""
    @Published var currentItems: [ArchiveItem] = []
    
    private var compressionManager: CompressionManager
    var archiveURL: URL?
    private var archiveFiles: [ArchiveFile] = []
    
    init(compressionManager: CompressionManager) {
        self.compressionManager = compressionManager
    }
    
    var pathComponents: [String] {
        guard !currentPath.isEmpty else { return [] }
        return currentPath.split(separator: "/").map(String.init)
    }
    
    func loadArchive(from url: URL) async throws {
        archiveURL = url
        _ = compressionManager.detectFormat(from: url) // Format detection for future use
        
        // Extract to temp location to browse structure
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveBrowse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: url,
            to: tempDir,
            progress: { _ in }
        )
        
        // Build archive structure from extracted files
        archiveFiles = extractedFiles.map { url in
            let relativePath = url.path.replacingOccurrences(of: tempDir.path + "/", with: "")
            return ArchiveFile(
                archivePath: relativePath,
                sourceURL: url,
                isDirectory: false
            )
        }
        
        // Build items list
        items = archiveFiles.map { file in
            ArchiveItem(
                path: file.archivePath,
                name: (file.archivePath as NSString).lastPathComponent,
                isDirectory: file.isDirectory,
                size: try? FileManager.default.attributesOfItem(atPath: file.sourceURL.path)[.size] as? Int64
            )
        }
        
        // Add directories
        let directories = Set(items.compactMap { item -> String? in
            let dirPath = (item.path as NSString).deletingLastPathComponent
            return dirPath.isEmpty ? nil : dirPath
        })
        
        for dirPath in directories {
            let dirName = (dirPath as NSString).lastPathComponent
            if !items.contains(where: { $0.path == dirPath && $0.isDirectory }) {
                items.append(ArchiveItem(path: dirPath, name: dirName, isDirectory: true, size: nil))
            }
        }
        
        currentPath = ""
        updateCurrentItems()
    }
    
    func createDirectory() {
        let dirName = "New Folder"
        let newPath = currentPath.isEmpty ? dirName : "\(currentPath)/\(dirName)"
        let newItem = ArchiveItem(path: newPath, name: dirName, isDirectory: true, size: nil)
        items.append(newItem)
        updateCurrentItems()
    }
    
    func addFiles() {
        // This will be handled by the parent view with file picker
        // The FinderStyleArchiveNavigator will call this via the toolbar button
    }
    
    func navigateUp() {
        if !currentPath.isEmpty {
            let components = currentPath.split(separator: "/")
            if components.count > 1 {
                currentPath = components.dropLast().joined(separator: "/")
            } else {
                currentPath = ""
            }
            updateCurrentItems()
        }
    }
    
    func navigateToPath(_ path: String) {
        currentPath = path
        updateCurrentItems()
    }
    
    func addFileToArchive(_ url: URL, at path: String) {
        // Ensure path doesn't start with /
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let archivePath = cleanPath.isEmpty ? url.lastPathComponent : "\(cleanPath)/\(url.lastPathComponent)"
        
        // Check if already exists
        if items.contains(where: { $0.path == archivePath }) {
            // Update existing item
            if let index = items.firstIndex(where: { $0.path == archivePath }) {
                items[index] = ArchiveItem(
                    path: archivePath,
                    name: url.lastPathComponent,
                    isDirectory: false,
                    size: try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
                )
            }
            // Update archive file
            if let fileIndex = archiveFiles.firstIndex(where: { $0.archivePath == archivePath }) {
                archiveFiles[fileIndex] = ArchiveFile(
                    archivePath: archivePath,
                    sourceURL: url,
                    isDirectory: false
                )
            }
        } else {
            let newItem = ArchiveItem(
                path: archivePath,
                name: url.lastPathComponent,
                isDirectory: false,
                size: try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64
            )
            items.append(newItem)
            
            // Add to archive files for saving
            archiveFiles.append(ArchiveFile(
                archivePath: archivePath,
                sourceURL: url,
                isDirectory: false
            ))
        }
        
        updateCurrentItems()
    }
    
    func getFilesForCompression() -> [URL] {
        return archiveFiles.map { $0.sourceURL }
    }
    
    func getFilePathsForCompression() -> [(url: URL, archivePath: String)] {
        return archiveFiles.map { (url: $0.sourceURL, archivePath: $0.archivePath) }
    }
    
    private func updateCurrentItems() {
        if currentPath.isEmpty {
            // Show root items (no directory prefix or just filename)
            currentItems = items.filter { item in
                let itemDir = (item.path as NSString).deletingLastPathComponent
                return itemDir.isEmpty || itemDir == "." || itemDir == currentPath
            }
        } else {
            // Show items in current directory
            currentItems = items.filter { item in
                let itemDir = (item.path as NSString).deletingLastPathComponent
                // Match exact path or path with trailing separator
                return itemDir == currentPath || itemDir == currentPath + "/"
            }
        }
        
        // Sort: directories first, then by name
        currentItems.sort { first, second in
            if first.isDirectory != second.isDirectory {
                return first.isDirectory
            }
            return first.name < second.name
        }
    }
    
    func saveArchive(to url: URL, format: CompressionFormat, compressionLevel: Int) async throws {
        // Get all files to compress with their archive paths
        let filesWithPaths = getFilePathsForCompression()
        guard !filesWithPaths.isEmpty else {
            throw CompressionError.invalidInput("No files to compress")
        }
        
        // For formats that support custom paths (like ZIP), we need to handle path mapping
        // For now, use the files directly - path mapping would require compressor support
        let filesToCompress = filesWithPaths.map { $0.url }
        
        // Use compression manager to create archive
        _ = try await compressionManager.compress(
            files: filesToCompress,
            to: url,
            format: format,
            compressionLevel: format == .zip ? compressionLevel : nil,
            progress: { _ in }
        )
        
        archiveURL = url
    }
}

