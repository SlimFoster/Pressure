import XCTest
import Security
@testable import Pressure

final class SplitZIPTests: XCTestCase {
    var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = CompressionTestHelpers.createTempDirectory()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        super.tearDown()
    }

    func testSplit_ProducesMultipleVolumesWithCorrectNaming() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        // Incompressible data so the archive is large enough to actually span volumes.
        let fileURL = sourceDir.appendingPathComponent("data.bin")
        try randomData(count: 300_000).write(to: fileURL)

        let unsplitURL = tempDirectory.appendingPathComponent("unsplit.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: unsplitURL, progress: { _ in })

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.zip")
        let volumes = try SplitZIPWriter.split(archiveURL: unsplitURL, volumeSize: 65536, outputBaseURL: outputBaseURL)

        XCTAssertGreaterThan(volumes.count, 1, "300KB of incompressible data at a 64KB volume size should span multiple volumes")
        XCTAssertEqual(volumes.last?.pathExtension, "zip")
        for volume in volumes.dropLast() {
            XCTAssertTrue(volume.pathExtension.hasPrefix("z"))
        }
    }

    func testSplitAndRejoin_RoundTripsToIdenticalContent() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let file1 = sourceDir.appendingPathComponent("one.bin")
        let file2 = sourceDir.appendingPathComponent("two.bin")
        try randomData(count: 150_000).write(to: file1)
        try randomData(count: 150_000).write(to: file2)

        let unsplitURL = tempDirectory.appendingPathComponent("unsplit.zip")
        _ = try await ZIPCompressor.compress(files: [file1, file2], outputURL: unsplitURL, progress: { _ in })
        let originalUnsplitData = try Data(contentsOf: unsplitURL)

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.zip")
        let volumes = try SplitZIPWriter.split(archiveURL: unsplitURL, volumeSize: 65536, outputBaseURL: outputBaseURL)
        XCTAssertGreaterThan(volumes.count, 1)

        let rejoinedURL = tempDirectory.appendingPathComponent("rejoined.zip")
        try SplitZIPArchive.rejoin(startingFrom: volumes.first!, to: rejoinedURL)

        // Byte-identical to the original except the EOCD's two disk-number fields, which are
        // deliberately patched to reflect the real volume count — everything else, including
        // every entry's local-header offset and the CD-offset field itself, is untouched.
        var expectedBytes = originalUnsplitData
        let eocdOffset = try ZIPBinaryUtilities.findEOCD(in: expectedBytes)
        let diskNumberPatch = withUnsafeBytes(of: UInt16(volumes.count - 1).littleEndian) { Data($0) }
        expectedBytes.replaceSubrange((eocdOffset + 4)..<(eocdOffset + 6), with: diskNumberPatch)
        expectedBytes.replaceSubrange((eocdOffset + 6)..<(eocdOffset + 8), with: diskNumberPatch)
        XCTAssertEqual(try Data(contentsOf: rejoinedURL), expectedBytes)

        // And, more importantly, the rejoined file must actually extract correctly.
        let entries = try await ZIPCompressor.listEntries(at: rejoinedURL)
        XCTAssertEqual(Set(entries.map(\.path)), ["one.bin", "two.bin"])

        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        let compressionManager = await CompressionManager()
        let extracted = try await compressionManager.decompress(file: rejoinedURL, to: extractDir, progress: { _ in })
        XCTAssertEqual(extracted.count, 2)
        for extractedFile in extracted {
            let originalFile = extractedFile.lastPathComponent == "one.bin" ? file1 : file2
            XCTAssertEqual(try Data(contentsOf: extractedFile), try Data(contentsOf: originalFile))
        }
    }

    func testSiblingVolumes_DiscoveredInOrderFromAnySegment() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("data.bin")
        try randomData(count: 300_000).write(to: fileURL)

        let unsplitURL = tempDirectory.appendingPathComponent("unsplit.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: unsplitURL, progress: { _ in })

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.zip")
        let volumes = try SplitZIPWriter.split(archiveURL: unsplitURL, volumeSize: 65536, outputBaseURL: outputBaseURL)
        XCTAssertGreaterThan(volumes.count, 2)

        // Starting the lookup from the *last* segment should still find every volume in order.
        // (Compare filenames, not full URLs — /var vs /private/var symlink resolution can differ
        // between FileManager.temporaryDirectory and contentsOfDirectory's canonicalized output.)
        let discovered = SplitZIPArchive.siblingVolumes(for: volumes.last!)
        XCTAssertEqual(discovered.map(\.lastPathComponent), volumes.map(\.lastPathComponent))
    }

    func testSmallArchive_FitsInSingleVolume_NoActualSplitting() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "small.txt", content: "tiny")

        let unsplitURL = tempDirectory.appendingPathComponent("unsplit.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: unsplitURL, progress: { _ in })

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.zip")
        let volumes = try SplitZIPWriter.split(archiveURL: unsplitURL, volumeSize: 10_000_000, outputBaseURL: outputBaseURL)

        XCTAssertEqual(volumes.count, 1)
        XCTAssertEqual(volumes.first?.pathExtension, "zip")
        let entries = try await ZIPCompressor.listEntries(at: volumes.first!)
        XCTAssertEqual(entries.map(\.path), ["small.txt"])
    }

    // MARK: - Structural cross-validation against Info-Zip's `zip -s` reference output

    private func infoZipAvailable() -> Bool {
        CompressionTestHelpers.checkCLIToolAvailable("zip")
    }

    func testCrossValidation_StructureMatchesInfoZipSplitConvention() async throws {
        guard infoZipAvailable() else {
            throw XCTSkip("zip CLI not available")
        }

        // Build a reference split archive with the real Info-Zip `zip -s` tool.
        let refDir = tempDirectory.appendingPathComponent("ref")
        try FileManager.default.createDirectory(at: refDir, withIntermediateDirectories: true)
        let refFile = refDir.appendingPathComponent("data.bin")
        try randomData(count: 200_000).write(to: refFile)

        let (_, zipExit) = try CompressionTestHelpers.runCLICommand(
            "/usr/bin/zip",
            arguments: ["-s", "64k", "reference.zip", "data.bin"],
            workingDirectory: refDir
        )
        XCTAssertEqual(zipExit, 0)

        let refVolumes = try FileManager.default.contentsOfDirectory(at: refDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("reference.z") }
        XCTAssertGreaterThan(refVolumes.count, 1, "Reference archive should have actually split")

        let refFirstVolume = refVolumes.first { $0.pathExtension == "z01" }!
        let refData = try Data(contentsOf: refFirstVolume)
        // First 4 bytes: spanning signature. Next 4: local file header signature.
        XCTAssertEqual(refData.prefix(4), Data([0x50, 0x4b, 0x07, 0x08]))
        XCTAssertEqual(refData[4..<8], Data([0x50, 0x4b, 0x03, 0x04]))

        // Now build Pressure's own split archive the same way and confirm the same structural
        // properties hold (signature placement, extension convention, final-volume EOCD disk
        // numbers matching the volume count).
        let mineSourceDir = tempDirectory.appendingPathComponent("mine")
        try FileManager.default.createDirectory(at: mineSourceDir, withIntermediateDirectories: true)
        let mineFile = mineSourceDir.appendingPathComponent("data.bin")
        try randomData(count: 200_000).write(to: mineFile)

        let unsplitURL = tempDirectory.appendingPathComponent("mine_unsplit.zip")
        _ = try await ZIPCompressor.compress(files: [mineFile], outputURL: unsplitURL, progress: { _ in })

        let outputBaseURL = tempDirectory.appendingPathComponent("mine.zip")
        let volumes = try SplitZIPWriter.split(archiveURL: unsplitURL, volumeSize: 65536, outputBaseURL: outputBaseURL)
        XCTAssertGreaterThan(volumes.count, 1)

        let mineFirstVolume = volumes.first!
        let mineData = try Data(contentsOf: mineFirstVolume)
        XCTAssertEqual(mineData.prefix(4), Data([0x50, 0x4b, 0x07, 0x08]))
        XCTAssertEqual(mineData[4..<8], Data([0x50, 0x4b, 0x03, 0x04]))

        let finalData = try Data(contentsOf: volumes.last!)
        let eocdOffset = try ZIPBinaryUtilities.findEOCD(in: finalData)
        let diskNumber = try finalData.readLE(at: eocdOffset + 4, as: UInt16.self)
        let cdStartDisk = try finalData.readLE(at: eocdOffset + 6, as: UInt16.self)
        XCTAssertEqual(Int(diskNumber), volumes.count - 1)
        XCTAssertEqual(Int(cdStartDisk), volumes.count - 1)
    }

    private func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw CompressionError.invalidInput("Failed to generate random test data")
        }
        return Data(bytes)
    }
}
