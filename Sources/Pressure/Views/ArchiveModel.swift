import SwiftUI

struct ArchiveItem {
    let path: String
    let name: String
    let isDirectory: Bool
    /// Original (uncompressed) size.
    let size: Int64?
    /// Compressed size within the archive, when known (ZIP only for now).
    var packedSize: Int64? = nil
    var dateModified: Date? = nil

    /// Fraction of size saved by compression, e.g. 0.25 for a 25% reduction.
    var ratio: Double? {
        guard let size, size > 0, let packedSize else { return nil }
        return 1.0 - (Double(packedSize) / Double(size))
    }
}

struct ArchiveStats {
    let itemCount: Int
    let originalSize: Int64
    let packedSize: Int64

    var savedPercent: Double? {
        guard originalSize > 0 else { return nil }
        return 1.0 - (Double(packedSize) / Double(originalSize))
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
    // Power mode's layout reactively branches on this (empty state vs. loaded), so it must be
    // @Published — it wasn't originally, which silently broke that branch since SwiftUI never
    // re-rendered on a plain-property change (the old UI only ever read it synchronously inside
    // button handlers, which masked the bug).
    @Published var archiveURL: URL?
    /// The password for the current archive session, when it's ZIP-encrypted. `nil` means the
    /// archive is (or will be, once committed) a plain, unencrypted archive.
    @Published var password: String?
    /// Non-nil means the archive is (or will be, once committed) split into numbered volumes at
    /// `archiveURL`'s location, each at most this many bytes.
    @Published var splitVolumeSize: Int64?
    /// When splitting is on, split volumes on disk aren't directly browsable/extractable without
    /// rejoining — so this holds a private, always-unsplit working copy that `extractedURL`/
    /// `getFilePathsForCompression` actually read from, kept in sync with `archiveURL`'s split
    /// output every time `commit()` runs. `nil` when splitting is off (browsing reads `archiveURL`
    /// directly, same as before splitting existed).
    private var splitWorkingCopyURL: URL?
    /// Real, already-on-disk source files added to the archive this session (drag/drop, Add Files) —
    /// distinct from entries that originated in the opened archive, which are extracted lazily via
    /// `extractedSourceURLs` only when their bytes are actually needed.
    private var archiveFiles: [ArchiveFile] = []
    private var extractedSourceURLs: [String: URL] = [:]
    private var scratchDirectory: URL?
    /// Maps an item's current (possibly renamed) path to the path it actually has in the
    /// on-disk archive at `archiveURL` right now. Needed because renaming only updates in-memory
    /// state until `commit()` rewrites the file — until then, lazy extraction must still ask the
    /// archive for the *original* entry name.
    private var originalArchivePaths: [String: String] = [:]

    init(compressionManager: CompressionManager) {
        self.compressionManager = compressionManager
    }

    var pathComponents: [String] {
        guard !currentPath.isEmpty else { return [] }
        return currentPath.split(separator: "/").map(String.init)
    }

    var archiveStats: ArchiveStats {
        let files = items.filter { !$0.isDirectory }
        let originalSize = files.reduce(Int64(0)) { $0 + ($1.size ?? 0) }
        let packedSize = files.reduce(Int64(0)) { $0 + ($1.packedSize ?? $1.size ?? 0) }
        return ArchiveStats(itemCount: files.count, originalSize: originalSize, packedSize: packedSize)
    }

    /// `password` only matters for ZIP archives that turn out to be AE-2 encrypted. If the
    /// archive is encrypted and no password (or the wrong one) is given, this throws
    /// `CompressionError.incorrectPassword` — callers should catch that specifically to prompt
    /// for a password (or a retry) rather than showing it as a generic failure.
    func loadArchive(from url: URL, password: String? = nil) async throws {
        archiveURL = url
        self.password = password
        archiveFiles = []
        extractedSourceURLs = [:]
        originalArchivePaths = [:]
        scratchDirectory = nil

        let format = compressionManager.detectFormat(from: url)

        if format == .zip, EncryptedZIPReader.isEncryptedZIP(at: url) {
            guard let password else {
                throw CompressionError.incorrectPassword
            }
            try EncryptedZIPReader.verifyPassword(at: url, password: password)

            let entries = try EncryptedZIPReader.listEntries(at: url)
            items = entries.map { entry in
                ArchiveItem(
                    path: entry.path,
                    name: (entry.path as NSString).lastPathComponent,
                    isDirectory: false,
                    size: entry.uncompressedSize,
                    packedSize: entry.packedSize,
                    dateModified: entry.modificationDate
                )
            }
        } else if format == .zip {
            // Read entry metadata straight from the central directory — no extraction needed
            // just to list contents, so opening even a large archive is instant.
            let entries = try await ZIPCompressor.listEntries(at: url)

            items = entries.map { entry in
                let normalizedPath = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
                return ArchiveItem(
                    path: normalizedPath,
                    name: (normalizedPath as NSString).lastPathComponent,
                    isDirectory: entry.isDirectory,
                    size: entry.isDirectory ? nil : entry.uncompressedSize,
                    packedSize: entry.isDirectory ? nil : entry.compressedSize,
                    dateModified: entry.modificationDate
                )
            }
        } else {
            // No cheap listing-without-extraction path exists yet for these formats, so fall
            // back to eager extraction, same as before — but cache the results so a later
            // save/export doesn't re-extract them.
            let tempDir = try scratchDirectoryURL()

            let extractedFiles = try await compressionManager.decompress(
                file: url,
                to: tempDir,
                progress: { _ in }
            )

            items = extractedFiles.map { fileURL in
                let relativePath = fileURL.path.replacingOccurrences(of: tempDir.path + "/", with: "")
                extractedSourceURLs[relativePath] = fileURL
                return ArchiveItem(
                    path: relativePath,
                    name: (relativePath as NSString).lastPathComponent,
                    isDirectory: false,
                    size: try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int64,
                    dateModified: try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date
                )
            }
        }

        for item in items where !item.isDirectory {
            originalArchivePaths[item.path] = item.path
        }
        synthesizeImpliedDirectories()

        currentPath = ""
        updateCurrentItems()
    }

    /// Ensures every implied ancestor directory of every item has an explicit `ArchiveItem` —
    /// some ZIPs omit directory entries, and `addFileToArchive` never creates one for a brand-new
    /// folder path on its own. Walks the full ancestor chain, not just the immediate parent, so
    /// multi-level new folders are fully represented (needed for the sidebar tree and rename).
    private func synthesizeImpliedDirectories() {
        var impliedDirPaths = Set<String>()
        for item in items {
            var dirPath = (item.path as NSString).deletingLastPathComponent
            while !dirPath.isEmpty {
                impliedDirPaths.insert(dirPath)
                dirPath = (dirPath as NSString).deletingLastPathComponent
            }
        }

        let existingDirPaths = Set(items.filter { $0.isDirectory }.map { $0.path })
        for dirPath in impliedDirPaths.subtracting(existingDirPaths) {
            let dirName = (dirPath as NSString).lastPathComponent
            items.append(ArchiveItem(path: dirPath, name: dirName, isDirectory: true, size: nil))
        }
    }

    /// Extracts a single entry's bytes on demand, caching the result. Cheap for ZIP (one entry at
    /// a time); for other formats this falls back to extracting the whole archive once.
    /// Where entry listing/extraction actually reads from — always a plain, unsplit archive
    /// file. Equal to `archiveURL` when splitting is off; the private working copy when on,
    /// since split volumes on disk aren't directly browsable without rejoining them first.
    private var readURL: URL? {
        splitWorkingCopyURL ?? archiveURL
    }

    func extractedURL(for item: ArchiveItem) async throws -> URL {
        precondition(!item.isDirectory)

        if let cached = extractedSourceURLs[item.path] {
            return cached
        }
        if let addedFile = archiveFiles.first(where: { $0.archivePath == item.path }) {
            return addedFile.sourceURL
        }
        guard let readURL else {
            throw CompressionError.invalidInput("No archive is open")
        }

        let dir = try scratchDirectoryURL()
        let format = compressionManager.detectFormat(from: readURL)
        // The archive on disk hasn't been rewritten yet if this item was renamed since load —
        // extract using the name it actually has there, not the current (possibly renamed) path.
        let onDiskPath = originalArchivePaths[item.path] ?? item.path

        if format == .zip {
            let outputURL = dir.appendingPathComponent(item.path)
            if let password {
                let data = try EncryptedZIPReader.extractEntry(path: onDiskPath, from: readURL, password: password)
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: outputURL)
            } else {
                try await ZIPCompressor.extractEntry(path: onDiskPath, from: readURL, to: outputURL)
            }
            extractedSourceURLs[item.path] = outputURL
            return outputURL
        }

        let extracted = try await compressionManager.decompress(file: readURL, to: dir, progress: { _ in })
        for fileURL in extracted {
            let relativePath = fileURL.path.replacingOccurrences(of: dir.path + "/", with: "")
            extractedSourceURLs[relativePath] = fileURL
        }
        guard let url = extractedSourceURLs[onDiskPath] else {
            throw CompressionError.decompressionFailed("Could not locate \(item.path) after extraction")
        }
        extractedSourceURLs[item.path] = url
        return url
    }

    private func scratchDirectoryURL() throws -> URL {
        if let scratchDirectory {
            return scratchDirectory
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveBrowse-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        scratchDirectory = dir
        return dir
    }

    /// Rewrites the archive at `archiveURL` from the current `items`, so edits (add/delete/
    /// rename) land on disk immediately — a "live editing session" rather than the old
    /// stage-then-Save-As flow. This is a full rebuild rather than true incremental editing
    /// (e.g. ZIPFoundation's `.update` mode): simpler and works identically across every
    /// format, at the cost of rewriting the whole archive per edit. Worth revisiting as an
    /// incremental-update optimization if this proves slow on large archives.
    func commit() async throws {
        guard let archiveURL else { return }

        let format = compressionManager.detectFormat(from: archiveURL)
        let filesWithPaths = try await getFilePathsForCompression()

        guard !filesWithPaths.isEmpty else {
            removeExistingSplitVolumes(baseURL: archiveURL)
            if let splitWorkingCopyURL {
                try? FileManager.default.removeItem(at: splitWorkingCopyURL)
                self.splitWorkingCopyURL = nil
            }
            return
        }

        if let splitVolumeSize {
            // Splitting needs a real, single, unsplit file to slice up — write that to a private
            // working copy (which also becomes `readURL`, so browsing/extraction keeps working
            // against a normal file rather than needing to understand split volumes), then split
            // *that* into the user-facing volumes at `archiveURL`.
            let workingCopy = try splitWorkingCopyURLCreatingIfNeeded()
            _ = try await compressionManager.compress(
                fileMappings: filesWithPaths,
                to: workingCopy,
                format: format,
                password: password,
                progress: { _ in }
            )

            removeExistingSplitVolumes(baseURL: archiveURL)
            if format == .zip {
                _ = try SplitZIPWriter.split(archiveURL: workingCopy, volumeSize: splitVolumeSize, outputBaseURL: archiveURL)
            } else {
                _ = try GenericSplitCompressor.split(fileURL: workingCopy, volumeSize: splitVolumeSize, outputBaseURL: archiveURL)
            }
        } else {
            if let splitWorkingCopyURL {
                try? FileManager.default.removeItem(at: splitWorkingCopyURL)
                self.splitWorkingCopyURL = nil
            }
            removeExistingSplitVolumes(baseURL: archiveURL) // clean up stray .z01/.001 etc from a previous split

            _ = try await compressionManager.compress(
                fileMappings: filesWithPaths,
                to: archiveURL,
                format: format,
                password: password,
                progress: { _ in }
            )
        }
    }

    private func splitWorkingCopyURLCreatingIfNeeded() throws -> URL {
        if let splitWorkingCopyURL { return splitWorkingCopyURL }
        let dir = try scratchDirectoryURL()
        let name = archiveURL?.lastPathComponent ?? "archive"
        let url = dir.appendingPathComponent("working-copy-\(name)")
        splitWorkingCopyURL = url
        return url
    }

    /// Removes any split volumes/parts left over at `baseURL`'s location from a previous split
    /// (both ZIP-spanning `.z01`/`.zip` and generic `.001`/`.002` naming), plus `baseURL` itself
    /// — so every commit starts from a clean slate rather than accumulating stale volumes from a
    /// larger previous split (e.g. switching from a small volume size to a larger one, or off).
    private func removeExistingSplitVolumes(baseURL: URL) {
        let directory = baseURL.deletingLastPathComponent()
        if let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let zipBase = baseURL.deletingPathExtension().lastPathComponent
            let genericBase = baseURL.lastPathComponent

            for candidate in contents {
                let ext = candidate.pathExtension
                let isZipVolume = candidate.deletingPathExtension().lastPathComponent == zipBase
                    && ext.count == 3 && ext.lowercased().hasPrefix("z") && Int(ext.dropFirst()) != nil
                let isGenericPart = candidate.deletingPathExtension().lastPathComponent == genericBase
                    && GenericSplitCompressor.isSplitPart(candidate)
                if isZipVolume || isGenericPart {
                    try? FileManager.default.removeItem(at: candidate)
                }
            }
        }
        if FileManager.default.fileExists(atPath: baseURL.path) {
            try? FileManager.default.removeItem(at: baseURL)
        }
    }

    func deleteItems(paths: Set<String>) async throws {
        guard !paths.isEmpty else { return }

        items.removeAll { item in
            paths.contains(item.path) || paths.contains(where: { item.path.hasPrefix($0 + "/") })
        }
        for path in paths {
            extractedSourceURLs.removeValue(forKey: path)
            originalArchivePaths.removeValue(forKey: path)
            archiveFiles.removeAll { $0.archivePath == path || $0.archivePath.hasPrefix(path + "/") }
        }

        updateCurrentItems()
        try await commit()
    }

    func renameItem(path: String, to newName: String) async throws {
        guard items.contains(where: { $0.path == path }) else { return }
        let parentPath = (path as NSString).deletingLastPathComponent
        let newPath = parentPath.isEmpty ? newName : "\(parentPath)/\(newName)"
        guard newPath != path else { return }
        guard !items.contains(where: { $0.path == newPath }) else {
            throw CompressionError.invalidInput("\"\(newName)\" already exists here")
        }

        let oldPrefix = path + "/"
        for i in items.indices {
            let oldItemPath = items[i].path
            guard oldItemPath == path || oldItemPath.hasPrefix(oldPrefix) else { continue }

            let remappedPath = oldItemPath == path
                ? newPath
                : newPath + "/" + oldItemPath.dropFirst(oldPrefix.count)

            let existing = items[i]
            items[i] = ArchiveItem(
                path: remappedPath,
                name: (remappedPath as NSString).lastPathComponent,
                isDirectory: existing.isDirectory,
                size: existing.size,
                packedSize: existing.packedSize,
                dateModified: existing.dateModified
            )

            if let cached = extractedSourceURLs.removeValue(forKey: oldItemPath) {
                extractedSourceURLs[remappedPath] = cached
            }
            if let originalPath = originalArchivePaths.removeValue(forKey: oldItemPath) {
                originalArchivePaths[remappedPath] = originalPath
            }
            if let fileIndex = archiveFiles.firstIndex(where: { $0.archivePath == oldItemPath }) {
                archiveFiles[fileIndex] = ArchiveFile(
                    archivePath: remappedPath,
                    sourceURL: archiveFiles[fileIndex].sourceURL,
                    isDirectory: archiveFiles[fileIndex].isDirectory
                )
            }
        }

        updateCurrentItems()
        try await commit()
    }

    func extractAll(to destinationDir: URL) async throws {
        for item in items where !item.isDirectory {
            let sourceURL = try await extractedURL(for: item)
            let destinationURL = destinationDir.appendingPathComponent(item.path)
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        }
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

        synthesizeImpliedDirectories()
        updateCurrentItems()
    }
    
    func getFilesForCompression() async throws -> [URL] {
        return try await getFilePathsForCompression().map { $0.url }
    }

    /// Resolves every file entry to a real on-disk URL, extracting any archive-originated
    /// entries that haven't been needed yet — this is where "lazy" extraction actually happens
    /// for files being re-compressed/saved.
    func getFilePathsForCompression() async throws -> [(url: URL, archivePath: String)] {
        var result: [(url: URL, archivePath: String)] = []
        for item in items where !item.isDirectory {
            let url = try await extractedURL(for: item)
            result.append((url: url, archivePath: item.path))
        }
        return result
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
        let filesWithPaths = try await getFilePathsForCompression()
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

