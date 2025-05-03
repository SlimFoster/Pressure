import Foundation
import SWCompression

struct BZIP2Compressor {
    static func compress(
        files: [URL],
        outputURL: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard let firstFile = files.first else {
            throw CompressionError.invalidInput("No files to compress")
        }
        
        if files.count > 1 {
            // For multiple files, create a tar.bz2
            return try await compressToTarBz2(files: files, outputURL: outputURL, progress: progress)
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileData = try Data(contentsOf: firstFile)
                    
                    // Compress using BZip2 from SWCompression
                    let compressedData = BZip2.compress(data: fileData)
                    
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
                    
                    // Decompress using BZip2 from SWCompression
                    let decompressedData = try BZip2.decompress(data: compressedData)
                    
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
    
    private static func compressToTarBz2(
        files: [URL],
        outputURL: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        // First create TAR
        let tempTarURL = outputURL.deletingPathExtension().appendingPathExtension("tar")
        let tarURL = try await TARCompressor.compress(files: files, outputURL: tempTarURL, progress: { _ in })
        
        // Then compress with BZip2
        let tarData = try Data(contentsOf: tarURL)
        let compressedData = BZip2.compress(data: tarData)
        try compressedData.write(to: outputURL)
        
        // Clean up temp TAR file
        try? FileManager.default.removeItem(at: tarURL)
        
        Task { @MainActor in
            await progress(1.0)
        }
        return outputURL
    }
}
