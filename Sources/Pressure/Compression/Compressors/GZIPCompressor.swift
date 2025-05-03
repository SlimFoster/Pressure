import Foundation
import SWCompression

struct GZIPCompressor {
    static func compress(
        files: [URL],
        outputURL: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard let firstFile = files.first else {
            throw CompressionError.invalidInput("No files to compress")
        }
        
        if files.count > 1 {
            // For multiple files, create a tar.gz
            return try await compressToTarGz(files: files, outputURL: outputURL, progress: progress)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileData = try Data(contentsOf: firstFile)
                    
                    // Compress using GZip from SWCompression
                    let compressedData = try GzipArchive.archive(data: fileData)
                    
                    try compressedData.write(to: outputURL)
                    
                    continuation.resume(returning: outputURL)
                    Task { @MainActor in
                        await progress(1.0)
                    }
                } catch {
                    continuation.resume(throwing: CompressionError.compressionFailed(error.localizedDescription))
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
                    let compressedData = try Data(contentsOf: file)
                    
                    // Decompress using GZip from SWCompression
                    let decompressedData = try GzipArchive.unarchive(archive: compressedData)
                    
                    let outputFileName = file.deletingPathExtension().lastPathComponent
                    let outputURL = outputDir.appendingPathComponent(outputFileName)
                    try decompressedData.write(to: outputURL)
                    
                    Task { @MainActor in
                        await progress(1.0)
                    }
                    continuation.resume(returning: [outputURL])
                } catch {
                    continuation.resume(throwing: CompressionError.decompressionFailed(error.localizedDescription))
                }
            }
        }
    }
    
    private static func compressToTarGz(
        files: [URL],
        outputURL: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        // First create TAR
        let tempTarURL = outputURL.deletingPathExtension().appendingPathExtension("tar")
        let tarURL = try await TARCompressor.compress(files: files, outputURL: tempTarURL, progress: { _ in })
        
        // Then compress with GZip
        let tarData = try Data(contentsOf: tarURL)
        let compressedData = try GzipArchive.archive(data: tarData)
        try compressedData.write(to: outputURL)
        
        // Clean up temp TAR file
        try? FileManager.default.removeItem(at: tarURL)
        
        Task { @MainActor in
            await progress(1.0)
        }
        return outputURL
    }
}
