import Foundation

/// Splits an already-complete ZIP file into numbered volumes per APPNOTE's split-archive naming
/// convention (`.z01`, `.z02`, ..., final segment `.zip`) and spanning signature, verified
/// empirically against Info-Zip's `zip -s` output (see SplitZIPArchive).
///
/// Scope, deliberately: this guarantees a byte-perfect round trip through Pressure's own
/// `SplitZIPArchive.rejoin` (and can, if needed, be re-derived from the exact same bytes
/// ZIPFoundation originally wrote). It does **not** implement true per-disk-local addressing —
/// real multi-volume ZIP requires patching every central-directory entry's "disk number start"
/// and "relative offset of local header" fields to be local to whichever disk each entry's data
/// actually landed on (entries can span a disk boundary mid-file), which only matters for a
/// *different* tool reading the raw `.z01`/`.zip` segments directly without rejoining them
/// first. Getting that fully general case right is real, further scope — not implemented here.
/// So: no field inside the original archive bytes is touched except the EOCD's two disk-number
/// fields (cosmetic — they don't affect Pressure's own read path, which always rejoins first).
enum SplitZIPWriter {
    static func split(archiveURL: URL, volumeSize: Int64, outputBaseURL: URL) throws -> [URL] {
        guard volumeSize > 0 else {
            throw CompressionError.invalidInput("Split volume size must be positive")
        }

        let originalData = try Data(contentsOf: archiveURL)

        // If the whole archive (plus the 4-byte spanning signature it would need) fits in one
        // volume anyway, there's nothing to actually split — write it unchanged, with no
        // signature, so it reads back as a perfectly ordinary ZIP.
        guard Int64(originalData.count) + 4 > volumeSize else {
            if FileManager.default.fileExists(atPath: outputBaseURL.path) {
                try FileManager.default.removeItem(at: outputBaseURL)
            }
            try originalData.write(to: outputBaseURL)
            return [outputBaseURL]
        }

        let eocdOffset = try ZIPBinaryUtilities.findEOCD(in: originalData)
        let centralDirOffset = Int(try originalData.readLE(at: eocdOffset + 16, as: UInt32.self))

        var stream = Data()
        stream.appendLE(SplitZIPArchive.spanningSignature)
        stream.append(originalData)
        // Every subsequent chunking decision operates on `stream` (signature-prefixed), but no
        // field *inside* the original bytes is altered — `rejoin` strips exactly those 4 bytes
        // back off, reproducing `originalData` exactly, so nothing needs to "know" about the
        // shift except the chunking boundaries themselves.
        let shiftedCDOffset = centralDirOffset + 4

        let baseName = outputBaseURL.deletingPathExtension().lastPathComponent
        let directory = outputBaseURL.deletingLastPathComponent()

        var volumes: [URL] = []
        var partNumber = 1
        var offset = 0

        while offset < shiftedCDOffset {
            let end = min(offset + Int(volumeSize), shiftedCDOffset)
            let chunk = stream.subdata(in: offset..<end)
            let volumeURL = directory.appendingPathComponent("\(baseName).\(String(format: "z%02d", partNumber))")
            try chunk.write(to: volumeURL)
            volumes.append(volumeURL)
            offset = end
            partNumber += 1
        }

        let directoryAndEOCD = stream.subdata(in: shiftedCDOffset..<stream.count)
        let eocdOffsetWithinDirectoryBlock = (eocdOffset + 4) - shiftedCDOffset
        let finalURL = outputBaseURL

        let lastBodyVolumeURL = volumes.isEmpty ? nil : volumes[volumes.count - 1]
        let lastBodyVolumeSize = lastBodyVolumeURL.map { (try? Data(contentsOf: $0))?.count ?? 0 } ?? 0
        let eocdOffsetInFinalFile: Int

        if let lastBodyVolumeURL, lastBodyVolumeSize + directoryAndEOCD.count <= Int(volumeSize) {
            // Room to append the CD+EOCD onto the tail of the last body chunk.
            var combined = try Data(contentsOf: lastBodyVolumeURL)
            eocdOffsetInFinalFile = combined.count + eocdOffsetWithinDirectoryBlock
            combined.append(directoryAndEOCD)
            try FileManager.default.removeItem(at: lastBodyVolumeURL)
            try combined.write(to: finalURL)
            volumes.removeLast()
        } else {
            // No room (or there was no body chunk at all) — the CD+EOCD becomes its own segment.
            eocdOffsetInFinalFile = eocdOffsetWithinDirectoryBlock
            try directoryAndEOCD.write(to: finalURL)
        }
        volumes.append(finalURL)

        try patchEOCDDiskNumbers(volumeCount: volumes.count, finalVolumeURL: finalURL, eocdOffset: eocdOffsetInFinalFile)

        return volumes
    }

    /// Cosmetic only (see the type doc comment) — sets the EOCD's "number of this disk" and
    /// "disk where the central directory starts" to the final segment's (0-indexed) volume
    /// number, matching what `zip -s` itself produces (confirmed by inspection), without
    /// touching the CD-offset field itself (which stays valid for Pressure's rejoin-first path).
    private static func patchEOCDDiskNumbers(volumeCount: Int, finalVolumeURL: URL, eocdOffset: Int) throws {
        var finalData = try Data(contentsOf: finalVolumeURL)
        guard eocdOffset >= 0, eocdOffset + 20 <= finalData.count,
              try finalData.readLE(at: eocdOffset, as: UInt32.self) == ZIPSignature.endOfCentralDirectory else {
            throw ZIPBinaryError.malformedArchive("Could not locate EOCD within the final split volume to patch disk numbers")
        }

        let diskNumber = UInt16(volumeCount - 1)
        try patchUInt16(in: &finalData, at: eocdOffset + 4, to: diskNumber)
        try patchUInt16(in: &finalData, at: eocdOffset + 6, to: diskNumber)

        try finalData.write(to: finalVolumeURL)
    }

    private static func patchUInt16(in data: inout Data, at offset: Int, to value: UInt16) throws {
        guard offset >= 0, offset + 2 <= data.count else {
            throw ZIPBinaryError.malformedArchive("Patch offset \(offset) out of range")
        }
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { data.replaceSubrange(offset..<(offset + 2), with: $0) }
    }
}
