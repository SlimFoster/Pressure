import Foundation

@MainActor
class CompressionManager: ObservableObject {
    
    func compress(
        files: [URL],
        to outputURL: URL,
        format: CompressionFormat,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        return try await compress(
            files: files,
            to: outputURL,
            format: format,
            compressionLevel: nil,
            progress: progress
        )
    }
    
    func compress(
        files: [URL],
        to outputURL: URL,
        format: CompressionFormat,
        compressionLevel: Int?,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard !files.isEmpty else {
            throw CompressionError.invalidInput("No files to compress")
        }
        
        await progress(0.0)
        
        switch format {
        case .zip:
            return try await ZIPCompressor.compress(files: files, outputURL: outputURL, compressionLevel: compressionLevel, progress: progress)
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
    
    /// Like `compress(files:to:format:compressionLevel:progress:)`, but preserves each file's
    /// path within the archive rather than flattening to its filename. Only ZIP honors the
    /// per-file paths today; other formats fall back to flat filenames, matching their existing
    /// (pre-existing, not new) behavior.
    ///
    /// `password` is meaningful for `.zip` only — when set, this routes to the hand-rolled
    /// WinZip AE-2 writer instead of ZIPFoundation, since ZIPFoundation has no encryption support.
    func compress(
        fileMappings: [(url: URL, archivePath: String)],
        to outputURL: URL,
        format: CompressionFormat,
        compressionLevel: Int? = nil,
        password: String? = nil,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard !fileMappings.isEmpty else {
            throw CompressionError.invalidInput("No files to compress")
        }

        await progress(0.0)

        if format == .zip, let password {
            return try await EncryptedZIPWriter.compress(
                fileMappings: fileMappings,
                outputURL: outputURL,
                password: password,
                progress: progress
            )
        }

        if format == .zip {
            return try await ZIPCompressor.compress(
                fileMappings: fileMappings,
                outputURL: outputURL,
                compressionLevel: compressionLevel,
                progress: progress
            )
        }

        return try await compress(
            files: fileMappings.map { $0.url },
            to: outputURL,
            format: format,
            compressionLevel: compressionLevel,
            progress: progress
        )
    }

    /// Produces the archive already split into numbered volumes, returning every volume/part
    /// file in order. The underlying mechanism differs by format:
    /// - **ZIP** uses real APPNOTE disk-spanning (`SplitZIPWriter`) — tool-recognizable naming
    ///   and spanning signature, verified against Info-Zip's `zip -s` reference output.
    /// - **GZIP/BZIP2/Z** have no spanning-aware container of their own, so this uses generic
    ///   byte-chunked splitting (`GenericSplitCompressor`) — universally `cat`-joinable.
    /// - **TAR** *also* uses generic byte-chunked splitting rather than GNU tar's multi-volume
    ///   continuation-header format. That's a deliberate scope call, not an oversight: GNU
    ///   multi-volume tar's binary layout is poorly documented and this dev machine has no GNU
    ///   tar available to verify against empirically (only BSD tar, which doesn't support it) —
    ///   attempting it without a way to verify correctness was judged too high-risk. Generic
    ///   chunking is still fully standards-compatible (any tool can `cat` the parts back
    ///   together), just not something GNU tar itself can read volume-by-volume directly.
    func compressSplit(
        fileMappings: [(url: URL, archivePath: String)],
        to outputURL: URL,
        format: CompressionFormat,
        compressionLevel: Int? = nil,
        password: String? = nil,
        splitSizeBytes: Int64,
        progress: @escaping (Double) async -> Void
    ) async throws -> [URL] {
        let scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent("PressureSplit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratchDir) }

        let scratchArchiveURL = scratchDir.appendingPathComponent(outputURL.lastPathComponent)
        _ = try await compress(
            fileMappings: fileMappings,
            to: scratchArchiveURL,
            format: format,
            compressionLevel: compressionLevel,
            password: password,
            progress: progress
        )

        if format == .zip {
            return try SplitZIPWriter.split(archiveURL: scratchArchiveURL, volumeSize: splitSizeBytes, outputBaseURL: outputURL)
        }
        return try GenericSplitCompressor.split(fileURL: scratchArchiveURL, volumeSize: splitSizeBytes, outputBaseURL: outputURL)
    }

    /// Rejoins a split archive's volumes/parts (given any one of them) back into a single,
    /// ordinary archive file, ready for the normal compress/decompress code paths. Dispatches by
    /// naming scheme: generic parts always end in a 3-digit number (`.001`, `.002`, ...)
    /// regardless of the format underneath, while ZIP spanning volumes use `.z01`/`.zip`.
    func rejoinSplit(startingFrom url: URL, to outputURL: URL) throws {
        if GenericSplitCompressor.isSplitPart(url) {
            try GenericSplitCompressor.rejoin(startingFrom: url, to: outputURL)
        } else {
            try SplitZIPArchive.rejoin(startingFrom: url, to: outputURL)
        }
    }

    /// `password` is meaningful for `.zip` only — when set, this routes to the hand-rolled
    /// WinZip AE-2 reader instead of ZIPFoundation (which can't even list an encrypted archive's
    /// entries, let alone extract them).
    func decompress(
        file: URL,
        to outputDir: URL,
        password: String? = nil,
        progress: @escaping (Double) async -> Void
    ) async throws -> [URL] {
        await progress(0.0)

        let format = detectFormat(from: file)

        if format == .zip, let password {
            let entries = try EncryptedZIPReader.listEntries(at: file)
            var extractedFiles: [URL] = []
            for (index, entry) in entries.enumerated() {
                let data = try EncryptedZIPReader.extractEntry(path: entry.path, from: file, password: password)
                let outputURL = outputDir.appendingPathComponent(entry.path)
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: outputURL)
                extractedFiles.append(outputURL)
                await progress(Double(index + 1) / Double(max(entries.count, 1)))
            }
            return extractedFiles
        }

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
