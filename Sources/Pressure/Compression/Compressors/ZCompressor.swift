import Foundation
import Compression

struct ZCompressor {
    static func compress(
        files: [URL],
        outputURL: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard let firstFile = files.first else {
            throw CompressionError.invalidInput("No files to compress")
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let fileData = try Data(contentsOf: firstFile)
                    
                    // Use Compression framework with LZ4 (note: Z format uses LZW, but LZ4 is closest available)
                    // Allocate buffer larger than input to handle expansion
                    let bufferSize = fileData.count + 1024
                    let compressedData = try fileData.withUnsafeBytes { inputBytes -> Data in
                        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
                        defer { buffer.deallocate() }
                        
                        let compressedSize = compression_encode_buffer(
                            buffer,
                            bufferSize,
                            inputBytes.bindMemory(to: UInt8.self).baseAddress!,
                            fileData.count,
                            nil,
                            COMPRESSION_LZ4
                        )
                        
                        guard compressedSize > 0 && compressedSize <= bufferSize else {
                            throw CompressionError.compressionFailed("Compression failed: buffer size issue")
                        }
                        
                        return Data(bytes: buffer, count: compressedSize)
                    }
                    
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
                    
                    // Estimate decompressed size (Z format doesn't store size, so we estimate)
                    // Start with a reasonable estimate and grow if needed
                    var estimatedSize = compressedData.count * 4
                    var resultData: Data?
                    
                    // Try decompression with increasing buffer sizes if needed
                    while resultData == nil && estimatedSize < compressedData.count * 20 {
                        resultData = compressedData.withUnsafeBytes { bytes -> Data? in
                            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: estimatedSize)
                            defer { buffer.deallocate() }
                            
                            let decompressedSize = compression_decode_buffer(
                                buffer,
                                estimatedSize,
                                bytes.bindMemory(to: UInt8.self).baseAddress!,
                                compressedData.count,
                                nil,
                                COMPRESSION_LZ4
                            )
                            
                            guard decompressedSize > 0 && decompressedSize <= estimatedSize else {
                                return nil
                            }
                            
                            return Data(bytes: buffer, count: decompressedSize)
                        }
                        
                        // If decompression failed, try with larger buffer
                        if resultData == nil {
                            estimatedSize *= 2
                        }
                    }
                    
                    guard let decompressedData = resultData else {
                        throw CompressionError.decompressionFailed("Decompression failed: unable to decompress")
                    }
                    
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
}
