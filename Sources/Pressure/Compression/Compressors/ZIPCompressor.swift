import Foundation
import AppKit
import ZIPFoundation

struct ZIPEntryInfo {
    let path: String
    let isDirectory: Bool
    let uncompressedSize: Int64
    let compressedSize: Int64
    let modificationDate: Date?
}

struct ZIPCompressor {
    /// Reads entry metadata straight from the archive's central directory, without extracting any file data.
    static func listEntries(at url: URL) async throws -> [ZIPEntryInfo] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let archive = try Archive(url: url, accessMode: .read)
                    let infos = archive.map { entry in
                        ZIPEntryInfo(
                            path: entry.path,
                            isDirectory: entry.type == .directory,
                            uncompressedSize: Int64(entry.uncompressedSize),
                            compressedSize: Int64(entry.compressedSize),
                            modificationDate: entry.fileAttributes[.modificationDate] as? Date
                        )
                    }
                    continuation.resume(returning: infos)
                } catch {
                    continuation.resume(throwing: CompressionError.decompressionFailed(error.localizedDescription))
                }
            }
        }
    }

    /// Extracts a single entry's bytes on demand, without touching the rest of the archive.
    static func extractEntry(path: String, from archiveURL: URL, to outputURL: URL) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let archive = try Archive(url: archiveURL, accessMode: .read)
                    guard let entry = archive[path] else {
                        continuation.resume(throwing: CompressionError.decompressionFailed("Entry not found: \(path)"))
                        return
                    }

                    let outputDirPath = outputURL.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: outputDirPath, withIntermediateDirectories: true)
                    _ = try archive.extract(entry, to: outputURL)

                    continuation.resume(returning: ())
                } catch {
                    continuation.resume(throwing: CompressionError.decompressionFailed(error.localizedDescription))
                }
            }
        }
    }

    static func compress(
        files: [URL],
        outputURL: URL,
        compressionLevel: Int? = nil,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        return try await compress(
            fileMappings: files.map { (url: $0, archivePath: $0.lastPathComponent) },
            outputURL: outputURL,
            compressionLevel: compressionLevel,
            progress: progress
        )
    }

    /// Like `compress(files:outputURL:...)`, but lets the caller control each entry's path
    /// within the archive (rather than always flattening to `lastPathComponent`) — needed to
    /// preserve folder structure when rebuilding an archive that has real subdirectories.
    static func compress(
        fileMappings: [(url: URL, archivePath: String)],
        outputURL: URL,
        compressionLevel: Int? = nil,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let coordinator = NSFileCoordinator()
                    var error: NSError?

                    coordinator.coordinate(writingItemAt: outputURL, options: [], error: &error) { url in
                        do {
                            // Remove existing file if it exists
                            if FileManager.default.fileExists(atPath: url.path) {
                                try FileManager.default.removeItem(at: url)
                            }

                            // Create ZIP archive using ZIPFoundation
                            let archive = try Archive(url: url, accessMode: .create)

                            for (index, mapping) in fileMappings.enumerated() {
                                try archive.addEntry(
                                    with: mapping.archivePath,
                                    fileURL: mapping.url,
                                    compressionMethod: .deflate
                                )

                                // Update progress
                                Task { @MainActor in
                                    await progress(Double(index + 1) / Double(fileMappings.count))
                                }
                            }

                            continuation.resume(returning: url)
                        } catch {
                            continuation.resume(throwing: CompressionError.compressionFailed(error.localizedDescription))
                        }
                    }

                    if let error = error {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    static func decompress(
        file: URL,
        to outputDir: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> [URL] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let archive = try Archive(url: file, accessMode: .read)
                    
                    var extractedFiles: [URL] = []
                    var entries: [Entry] = []
                    for entry in archive {
                        entries.append(entry)
                    }
                    
                    for (index, entry) in entries.enumerated() {
                        let outputURL = outputDir.appendingPathComponent(entry.path)
                        
                        // Create directory if needed
                        let outputDirPath = outputURL.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: outputDirPath, withIntermediateDirectories: true)
                        
                        // Extract file
                        _ = try archive.extract(entry, to: outputURL)
                        
                        extractedFiles.append(outputURL)
                        
                        // Update progress
                        Task { @MainActor in
                            await progress(Double(index + 1) / Double(entries.count))
                        }
                    }
                    
                    continuation.resume(returning: extractedFiles)
                } catch {
                    continuation.resume(throwing: CompressionError.decompressionFailed(error.localizedDescription))
                }
            }
        }
    }
}
