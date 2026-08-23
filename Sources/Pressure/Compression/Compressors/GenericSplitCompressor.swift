import Foundation

/// Generic byte-chunked splitting for formats with no spanning-aware container of their own
/// (GZIP, BZIP2, Z) — unlike ZIP's disk-spanning or TAR's multi-volume mode, a single-stream
/// compressed file has no internal concept of "volumes", so splitting here just means slicing
/// the finished file into fixed-size numbered parts with no header at all. Reconstruction is
/// exactly `cat part.001 part.002 ... > original` — the same universally-interoperable approach
/// any tool (or a person, by hand) can perform, which is what makes this genuinely
/// standards-compatible despite not being format-native: nothing about the split needs the
/// receiving tool to understand splitting, only plain concatenation.
enum GenericSplitCompressor {
    static func split(fileURL: URL, volumeSize: Int64, outputBaseURL: URL) throws -> [URL] {
        guard volumeSize > 0 else {
            throw CompressionError.invalidInput("Split volume size must be positive")
        }

        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        let baseName = outputBaseURL.lastPathComponent
        let directory = outputBaseURL.deletingLastPathComponent()

        guard Int64(data.count) > volumeSize else {
            // Nothing to split — write it through unchanged.
            if FileManager.default.fileExists(atPath: outputBaseURL.path) {
                try FileManager.default.removeItem(at: outputBaseURL)
            }
            try data.write(to: outputBaseURL)
            return [outputBaseURL]
        }

        var volumes: [URL] = []
        var offset = 0
        var partNumber = 1

        while offset < data.count {
            let end = min(offset + Int(volumeSize), data.count)
            let chunk = data.subdata(in: offset..<end)
            let volumeURL = directory.appendingPathComponent("\(baseName).\(String(format: "%03d", partNumber))")
            try chunk.write(to: volumeURL)
            volumes.append(volumeURL)
            offset = end
            partNumber += 1
        }

        return volumes
    }

    /// Finds every part belonging to the same split file as `url` (by `name.ext.001`,
    /// `name.ext.002`, ... naming), in order — mirrors `SplitZIPArchive.siblingVolumes`.
    static func siblingVolumes(for url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let base = baseNameWithoutPartExtension(url)

        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [url]
        }

        let numbered = contents.compactMap { candidate -> (Int, URL)? in
            guard baseNameWithoutPartExtension(candidate) == base else { return nil }
            let ext = candidate.pathExtension
            guard ext.count == 3, let number = Int(ext) else { return nil }
            return (number, candidate)
        }

        guard !numbered.isEmpty else { return [url] }
        return numbered.sorted { $0.0 < $1.0 }.map(\.1)
    }

    private static func baseNameWithoutPartExtension(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    static func rejoin(startingFrom url: URL, to outputURL: URL) throws {
        let parts = siblingVolumes(for: url)
        guard !parts.isEmpty else {
            throw CompressionError.decompressionFailed("Could not locate split file parts")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let handle = try FileHandle(forWritingTo: outputURL)
        defer { try? handle.close() }

        for partURL in parts {
            handle.write(try Data(contentsOf: partURL, options: .mappedIfSafe))
        }
    }

    static func isSplitPart(_ url: URL) -> Bool {
        Int(url.pathExtension) != nil && url.pathExtension.count == 3
    }
}
