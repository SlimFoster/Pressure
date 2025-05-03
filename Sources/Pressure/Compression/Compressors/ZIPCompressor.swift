import Foundation
import AppKit
import ZIPFoundation

struct ZIPCompressor {
    static func compress(
        files: [URL],
        outputURL: URL,
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
                            
                            for (index, fileURL) in files.enumerated() {
                                try archive.addEntry(
                                    with: fileURL.lastPathComponent,
                                    fileURL: fileURL,
                                    compressionMethod: .deflate
                                )
                                
                                // Update progress
                                Task { @MainActor in
                                    await progress(Double(index + 1) / Double(files.count))
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
