import Foundation

@MainActor
class CompressionManager: ObservableObject {
    
    func compress(
        files: [URL],
        to outputURL: URL,
        format: CompressionFormat,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard !files.isEmpty else {
            throw CompressionError.invalidInput("No files to compress")
        }
        
        await progress(0.0)
        
        switch format {
        case .zip:
            return try await ZIPCompressor.compress(files: files, outputURL: outputURL, progress: progress)
        case .gzip:
            return try await GZIPCompressor.compress(files: files, outputURL: outputURL, progress: progress)
        case .tar:
            return try await TARCompressor.compress(files: files, outputURL: outputURL, progress: progress)
        case .bzip2:
            return try await BZIP2Compressor.compress(files: files, outputURL: outputURL, progress: progress)
        case .z:
            return try await ZCompressor.compress(files: files, outputURL: outputURL, progress: progress)
        case .rar:
            throw CompressionError.unsupportedFormat("RAR compression requires external library")
        }
    }
    
    func decompress(
        file: URL,
        to outputDir: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> [URL] {
        await progress(0.0)
        
        let format = detectFormat(from: file)
        
        switch format {
        case .zip:
            return try await ZIPCompressor.decompress(file: file, to: outputDir, progress: progress)
        case .gzip:
            return try await GZIPCompressor.decompress(file: file, to: outputDir, progress: progress)
        case .tar:
            return try await TARCompressor.decompress(file: file, to: outputDir, progress: progress)
        case .bzip2:
            return try await BZIP2Compressor.decompress(file: file, to: outputDir, progress: progress)
        case .z:
            return try await ZCompressor.decompress(file: file, to: outputDir, progress: progress)
        case .rar:
            throw CompressionError.unsupportedFormat("RAR decompression requires external library")
        }
    }
    
    // MARK: - Helper Methods
    
    func detectFormat(from url: URL) -> CompressionFormat {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "zip":
            return .zip
        case "gz", "gzip":
            return .gzip
        case "tar":
            return .tar
        case "bz2", "bzip2":
            return .bzip2
        case "z":
            return .z
        case "rar":
            return .rar
        default:
            return .zip // Default fallback
        }
    }
}
