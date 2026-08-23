import XCTest
import Security
@testable import Pressure

final class GenericSplitCompressorTests: XCTestCase {
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

    func testSplit_ProducesCorrectlyNamedParts() throws {
        let fileURL = tempDirectory.appendingPathComponent("data.gz")
        try randomData(count: 250_000).write(to: fileURL)

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.gz")
        let parts = try GenericSplitCompressor.split(fileURL: fileURL, volumeSize: 100_000, outputBaseURL: outputBaseURL)

        XCTAssertEqual(parts.count, 3) // 100k + 100k + 50k
        XCTAssertEqual(parts.map(\.lastPathComponent), ["archive.gz.001", "archive.gz.002", "archive.gz.003"])
    }

    func testSplitAndRejoin_ByteIdenticalToOriginal() throws {
        let fileURL = tempDirectory.appendingPathComponent("data.bz2")
        let original = try randomData(count: 333_333)
        try original.write(to: fileURL)

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.bz2")
        let parts = try GenericSplitCompressor.split(fileURL: fileURL, volumeSize: 50_000, outputBaseURL: outputBaseURL)
        XCTAssertGreaterThan(parts.count, 1)

        let rejoinedURL = tempDirectory.appendingPathComponent("rejoined.bz2")
        try GenericSplitCompressor.rejoin(startingFrom: parts.first!, to: rejoinedURL)

        XCTAssertEqual(try Data(contentsOf: rejoinedURL), original)
    }

    func testRejoin_FindsSiblingsStartingFromAnyPart() throws {
        let fileURL = tempDirectory.appendingPathComponent("data.Z")
        try randomData(count: 250_000).write(to: fileURL)

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.Z")
        let parts = try GenericSplitCompressor.split(fileURL: fileURL, volumeSize: 100_000, outputBaseURL: outputBaseURL)
        XCTAssertEqual(parts.count, 3)

        let discovered = GenericSplitCompressor.siblingVolumes(for: parts[1]) // start from the middle part
        XCTAssertEqual(discovered.map(\.lastPathComponent), parts.map(\.lastPathComponent))
    }

    func testSmallFile_FitsInOnePart_NoActualSplitting() throws {
        let fileURL = tempDirectory.appendingPathComponent("data.gz")
        try randomData(count: 1000).write(to: fileURL)

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.gz")
        let parts = try GenericSplitCompressor.split(fileURL: fileURL, volumeSize: 10_000_000, outputBaseURL: outputBaseURL)

        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts.first?.lastPathComponent, "archive.gz")
    }

    // MARK: - Cross-validation: Pressure's chunks must be plain-`cat`-joinable by any tool,
    // and independently splittable/joinable via the real `/usr/bin/split` too.

    func testCrossValidation_RejoinedWithRealCatCommand() throws {
        guard CompressionTestHelpers.checkCLIToolAvailable("cat") else {
            throw XCTSkip("cat not available")
        }

        let fileURL = tempDirectory.appendingPathComponent("data.gz")
        let original = try randomData(count: 200_000)
        try original.write(to: fileURL)

        let outputBaseURL = tempDirectory.appendingPathComponent("archive.gz")
        let parts = try GenericSplitCompressor.split(fileURL: fileURL, volumeSize: 65536, outputBaseURL: outputBaseURL)
        XCTAssertGreaterThan(parts.count, 1)

        let catOutputURL = tempDirectory.appendingPathComponent("cat_joined.gz")
        let (_, exitCode) = try CompressionTestHelpers.runCLICommand(
            "/bin/sh",
            arguments: ["-c", "cat \(parts.map { "'\($0.path)'" }.joined(separator: " ")) > '\(catOutputURL.path)'"]
        )
        XCTAssertEqual(exitCode, 0)
        XCTAssertEqual(try Data(contentsOf: catOutputURL), original)
    }

    func testCrossValidation_RealSplitCommandProducesCompatibleParts() throws {
        guard CompressionTestHelpers.checkCLIToolAvailable("split") else {
            throw XCTSkip("split not available")
        }

        let fileURL = tempDirectory.appendingPathComponent("data.gz")
        let original = try randomData(count: 200_000)
        try original.write(to: fileURL)

        let splitDir = tempDirectory.appendingPathComponent("split_ref")
        try FileManager.default.createDirectory(at: splitDir, withIntermediateDirectories: true)
        let (_, exitCode) = try CompressionTestHelpers.runCLICommand(
            "/usr/bin/split",
            arguments: ["-b", "65536", fileURL.path, "part."],
            workingDirectory: splitDir
        )
        XCTAssertEqual(exitCode, 0)

        let refParts = try FileManager.default.contentsOfDirectory(at: splitDir, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("part.") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertGreaterThan(refParts.count, 1)

        var rejoined = Data()
        for part in refParts {
            rejoined.append(try Data(contentsOf: part))
        }
        XCTAssertEqual(rejoined, original, "Pressure's own split file, when split by the real `split` tool and rejoined, must reproduce the original byte-for-byte")
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
