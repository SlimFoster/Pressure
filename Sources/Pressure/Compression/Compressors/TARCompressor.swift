import Foundation
import SWCompression

struct TARCompressor {
    static func compress(
        files: [URL],
        outputURL: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        return try await Task.detached(priority: .userInitiated) {
            // Store TAR entries as tuples since we're creating TAR format manually
            var tarEntries: [(name: String, size: Int, modificationDate: Date, data: Data)] = []
            
            do {
                for (index, fileURL) in files.enumerated() {
                    let fileData = try Data(contentsOf: fileURL)
                    let fileName = fileURL.lastPathComponent
                    
                    // Get file attributes
                    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
                    let fileSize = attributes[.size] as? UInt64 ?? UInt64(fileData.count)
                    let modificationDate = attributes[.modificationDate] as? Date ?? Date()
                    
                    // Store entry info for TAR header creation (we'll create TAR format manually)
                    tarEntries.append((
                        name: fileName,
                        size: Int(fileSize),
                        modificationDate: modificationDate,
                        data: fileData
                    ))
                    
                    // Update progress
                    Task { @MainActor in
                        await progress(Double(index + 1) / Double(files.count))
                    }
                }
                
                // Create TAR container and write to file
                // SWCompression doesn't support creating TAR files, so we implement basic TAR format
                var tarData = Data()
                for entry in tarEntries {
                    // Write TAR entry header and data
                    let header = try createTarHeader(name: entry.name, size: entry.size, modificationDate: entry.modificationDate)
                    tarData.append(header)
                    tarData.append(entry.data)
                    // Pad to 512-byte boundary
                    let padding = (512 - (entry.data.count % 512)) % 512
                    tarData.append(Data(count: padding))
                }
                // Add two empty blocks at end
                tarData.append(Data(count: 1024))
                
                try tarData.write(to: outputURL)
                
                return outputURL
            } catch {
                throw CompressionError.compressionFailed(error.localizedDescription)
            }
        }.value
    }
    
    static func decompress(
        file: URL,
        to outputDir: URL,
        progress: @escaping (Double) async -> Void
    ) async throws -> [URL] {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let tarData = try Data(contentsOf: file)
                    let tarContainer = try TarContainer.open(container: tarData)
                    
                    var extractedFiles: [URL] = []
                    let entries = Array(tarContainer)
                    
                    for (index, entry) in entries.enumerated() {
                        let fileName = entry.info.name
                        let outputURL = outputDir.appendingPathComponent(fileName)
                        
                        // Create directory if needed
                        let outputDirPath = outputURL.deletingLastPathComponent()
                        try FileManager.default.createDirectory(at: outputDirPath, withIntermediateDirectories: true)
                        
                        // Extract file data - entry.data is the file data directly
                        if let fileData = entry.data {
                            try fileData.write(to: outputURL)
                        } else {
                            // If data is nil, create empty file
                            try Data().write(to: outputURL)
                        }
                        
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
    
    // MARK: - Helper Methods
    
    static func createTarHeader(name: String, size: Int, modificationDate: Date) throws -> Data {
        var header = Data(count: 512)
        var offset = 0
        
        // Name (100 bytes)
        let nameData = name.data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 100, offset + nameData.count), with: nameData)
        offset += 100
        
        // Mode (8 bytes) - default to 0644
        let mode = "0000644"
        let modeData = mode.data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 8, offset + modeData.count), with: modeData)
        offset += 8
        
        // UID (8 bytes) - default to 0
        let uid = "0000000"
        let uidData = uid.data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 8, offset + uidData.count), with: uidData)
        offset += 8
        
        // GID (8 bytes) - default to 0
        let gid = "0000000"
        let gidData = gid.data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 8, offset + gidData.count), with: gidData)
        offset += 8
        
        // Size (12 bytes)
        let sizeStr = String(format: "%011o", size)
        let sizeData = sizeStr.data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 12, offset + sizeData.count), with: sizeData)
        offset += 12
        
        // Modification time (12 bytes)
        let mtime = Int(modificationDate.timeIntervalSince1970)
        let mtimeStr = String(format: "%011o", mtime)
        let mtimeData = mtimeStr.data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 12, offset + mtimeData.count), with: mtimeData)
        offset += 12
        
        // Type flag (1 byte) - default to regular file (0)
        // Check if it's a regular file type
        let typeFlag: UInt8 = 0 // Default to regular file
        header[offset] = typeFlag
        offset += 1
        
        // Link name (100 bytes) - already zeroed
        offset += 100
        
        // Magic (6 bytes) "ustar\0"
        let magic = "ustar\0".data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 6, offset + magic.count), with: magic)
        offset += 6
        
        // Version (2 bytes) "00"
        let version = "00".data(using: .utf8) ?? Data()
        header.replaceSubrange(offset..<min(offset + 2, offset + version.count), with: version)
        offset += 2
        
        // Calculate checksum (simple sum of all bytes)
        var checksum: UInt32 = 0
        for i in 0..<512 {
            if i < 148 || i >= 156 { // Skip checksum field itself
                checksum += UInt32(header[i])
            }
        }
        checksum += UInt32(8 * 32) // Add spaces for checksum field
        
        // Write checksum (8 bytes)
        let checksumStr = String(format: "%06o", checksum) + "\0 "
        let checksumData = checksumStr.data(using: .utf8) ?? Data()
        header.replaceSubrange(148..<min(156, 148 + checksumData.count), with: checksumData)
        
        return header
    }
}
