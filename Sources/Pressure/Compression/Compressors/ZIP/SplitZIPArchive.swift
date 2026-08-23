import Foundation

/// Shared constants and volume discovery/rejoin logic for APPNOTE-style split ZIP archives,
/// verified empirically against Info-Zip's `zip -s` reference output (segments named
/// `archive.z01`, `archive.z02`, ..., with the *final* segment keeping the `.zip` extension so
/// tools can quickly locate it and read the central directory).
enum SplitZIPArchive {
    /// Marks the first 4 bytes of a split archive's first segment when there are 2+ segments.
    static let spanningSignature: UInt32 = 0x08074b50
    /// Used instead of `spanningSignature` when splitting was requested but everything fit in
    /// one segment anyway (so there's really only a single, ordinary-shaped file).
    static let temporarySpanningMarker: UInt32 = 0x30304b50

    /// Finds every segment belonging to the same split archive as `url`, in volume order
    /// (`.z01`, `.z02`, ..., then the final `.zip` segment) — the naming convention is how a
    /// reader locates the sibling volumes, since there's nothing inside a `.z01` file itself
    /// that names its `.zip` counterpart.
    static func siblingVolumes(for url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let base = baseName(of: url)

        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [url]
        }

        var numbered: [(Int, URL)] = []
        var finalSegment: URL?

        for candidate in contents {
            guard baseName(of: candidate) == base else { continue }
            let ext = candidate.pathExtension
            if ext.lowercased() == "zip" {
                finalSegment = candidate
            } else if ext.count == 3, ext.lowercased().hasPrefix("z"), let number = Int(ext.dropFirst()) {
                numbered.append((number, candidate))
            }
        }

        guard let finalSegment else { return [url] }
        let ordered = numbered.sorted { $0.0 < $1.0 }.map(\.1) + [finalSegment]
        return ordered
    }

    private static func baseName(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// Rejoins a split archive's volumes into a single, ordinary (unsplit) ZIP file — after
    /// this, the result can be handed to the normal `ZIPCompressor`/`EncryptedZIPReader` code
    /// paths exactly as if it had never been split.
    static func rejoin(startingFrom url: URL, to outputURL: URL) throws {
        let volumes = siblingVolumes(for: url)
        guard !volumes.isEmpty else {
            throw CompressionError.decompressionFailed("Could not locate split archive volumes")
        }

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let outHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outHandle.close() }

        for (index, volumeURL) in volumes.enumerated() {
            var data = try Data(contentsOf: volumeURL)
            if index == 0, data.count >= 4 {
                let signature = try data.readLE(at: 0, as: UInt32.self)
                if signature == spanningSignature || signature == temporarySpanningMarker {
                    data = data.subdata(in: 4..<data.count)
                }
            }
            outHandle.write(data)
        }
    }

    /// True if `url` is a split archive's first segment (as opposed to a single, unsplit ZIP, or
    /// some other file entirely) — checked by the spanning signature at its very start.
    static func isSplitFirstSegment(_ url: URL) -> Bool {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { return false }
        defer { try? handle.close() }
        let header = handle.readData(ofLength: 4)
        guard header.count == 4 else { return false }
        let signature = UInt32(header[0]) | (UInt32(header[1]) << 8) | (UInt32(header[2]) << 16) | (UInt32(header[3]) << 24)
        return signature == spanningSignature || signature == temporarySpanningMarker
    }
}
