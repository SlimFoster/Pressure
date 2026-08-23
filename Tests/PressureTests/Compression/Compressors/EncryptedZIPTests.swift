import XCTest
@testable import Pressure

final class EncryptedZIPTests: XCTestCase {
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

    func testRoundTrip_SingleFile_CorrectPassword() async throws {
        let fileURL = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "secret.txt", content: "for your eyes only")
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "secret.txt")],
            outputURL: zipURL,
            password: "correct horse battery staple",
            progress: { _ in }
        )

        let extracted = try EncryptedZIPReader.extractEntry(path: "secret.txt", from: zipURL, password: "correct horse battery staple")
        XCTAssertEqual(String(data: extracted, encoding: .utf8), "for your eyes only")
    }

    func testRoundTrip_MultipleFilesWithNestedPaths() async throws {
        let file1 = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "guidelines.pdf", content: "brand guidelines content")
        let file2 = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "readme.md", content: "top level readme")
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [
                (url: file1, archivePath: "Brand/guidelines.pdf"),
                (url: file2, archivePath: "readme.md")
            ],
            outputURL: zipURL,
            password: "hunter2",
            progress: { _ in }
        )

        let entries = try EncryptedZIPReader.listEntries(at: zipURL)
        XCTAssertEqual(Set(entries.map(\.path)), ["Brand/guidelines.pdf", "readme.md"])

        let extracted1 = try EncryptedZIPReader.extractEntry(path: "Brand/guidelines.pdf", from: zipURL, password: "hunter2")
        XCTAssertEqual(String(data: extracted1, encoding: .utf8), "brand guidelines content")
        let extracted2 = try EncryptedZIPReader.extractEntry(path: "readme.md", from: zipURL, password: "hunter2")
        XCTAssertEqual(String(data: extracted2, encoding: .utf8), "top level readme")
    }

    func testExtractEntry_WrongPassword_ThrowsIncorrectPassword() async throws {
        let fileURL = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "secret.txt", content: "for your eyes only")
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "secret.txt")],
            outputURL: zipURL,
            password: "correct password",
            progress: { _ in }
        )

        do {
            _ = try EncryptedZIPReader.extractEntry(path: "secret.txt", from: zipURL, password: "wrong password")
            XCTFail("Expected incorrectPassword to be thrown")
        } catch CompressionError.incorrectPassword {
            // expected
        } catch {
            XCTFail("Expected CompressionError.incorrectPassword, got \(error)")
        }
    }

    func testListEntries_ReportsCorrectSizes() async throws {
        let content = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 200)
        let fileURL = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "compressible.txt", content: content)
        let originalSize = try CompressionTestHelpers.getFileSize(at: fileURL)
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "compressible.txt")],
            outputURL: zipURL,
            password: "pw",
            progress: { _ in }
        )

        let entries = try EncryptedZIPReader.listEntries(at: zipURL)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.uncompressedSize, originalSize)
        XCTAssertGreaterThan(entry.packedSize, 0)
        XCTAssertLessThan(entry.packedSize, originalSize)
    }

    func testRoundTrip_EmptyFile() async throws {
        let fileURL = try CompressionTestHelpers.createEmptyFile(in: tempDirectory, name: "empty.txt")
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "empty.txt")],
            outputURL: zipURL,
            password: "pw",
            progress: { _ in }
        )

        let extracted = try EncryptedZIPReader.extractEntry(path: "empty.txt", from: zipURL, password: "pw")
        XCTAssertEqual(extracted.count, 0)
    }

    func testRoundTrip_LargerThanOneBlock() async throws {
        // Exercises the CTR counter incrementing across many 16-byte blocks, not just the first.
        let fileURL = try CompressionTestHelpers.createLargeFile(in: tempDirectory, name: "large.bin", sizeInMB: 2)
        let originalData = try Data(contentsOf: fileURL)
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "large.bin")],
            outputURL: zipURL,
            password: "pw",
            progress: { _ in }
        )

        let extracted = try EncryptedZIPReader.extractEntry(path: "large.bin", from: zipURL, password: "pw")
        XCTAssertEqual(extracted, originalData)
    }

    // MARK: - Cross-validation against pyzipper (an independent WinZip-AES implementation)
    //
    // Round-tripping only through Pressure's own reader/writer isn't sufficient proof of real
    // AE-2 compliance — a mirrored mistake in both would pass silently. These tests shell out to
    // `python3 -c "import pyzipper; ..."` in both directions to prove interop with something
    // Pressure didn't write itself. Requires `pip install pyzipper`; skipped if unavailable.

    /// The test runner's PATH doesn't necessarily include wherever `pip install pyzipper` put
    /// python3 (e.g. python.org's /Library/Frameworks install, vs. Xcode's minimal test PATH),
    /// so resolve it explicitly rather than relying on `env`.
    private static let python3Path: String? = {
        let candidates = [
            "/usr/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3"
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            if (try? CompressionTestHelpers.runCLICommand(path, arguments: ["-c", "import pyzipper"]).exitCode) == 0 {
                return path
            }
        }
        return nil
    }()

    private func pyzipperAvailable() -> Bool {
        Self.python3Path != nil
    }

    func testCrossValidation_PressureWrites_PyzipperReads() async throws {
        guard pyzipperAvailable() else {
            throw XCTSkip("pyzipper not installed (pip install pyzipper)")
        }

        let fileURL = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "note.txt", content: "cross-validated content")
        let zipURL = tempDirectory.appendingPathComponent("pressure_wrote.zip")
        let password = "sw0rdfish"

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "note.txt")],
            outputURL: zipURL,
            password: password,
            progress: { _ in }
        )

        let script = """
        import pyzipper, sys
        with pyzipper.AESZipFile(sys.argv[1]) as zf:
            zf.setpassword(sys.argv[2].encode())
            print(zf.read('note.txt').decode(), end='')
        """
        let scriptURL = tempDirectory.appendingPathComponent("read.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let (output, exitCode) = try CompressionTestHelpers.runCLICommand(
            Self.python3Path!,
            arguments: [scriptURL.path, zipURL.path, password]
        )
        XCTAssertEqual(exitCode, 0, "pyzipper failed to read Pressure's output: \(output)")
        XCTAssertEqual(output, "cross-validated content")
    }

    func testCrossValidation_PyzipperWrites_PressureReads() throws {
        guard pyzipperAvailable() else {
            throw XCTSkip("pyzipper not installed (pip install pyzipper)")
        }

        let zipURL = tempDirectory.appendingPathComponent("pyzipper_wrote.zip")
        let password = "correcthorsebatterystaple"

        let script = """
        import pyzipper, sys
        with pyzipper.AESZipFile(sys.argv[1], 'w', encryption=pyzipper.WZ_AES, encryption_kwargs={'nbits': 256}) as zf:
            zf.setpassword(sys.argv[2].encode())
            zf.writestr('hello.txt', 'written by pyzipper')
        """
        let scriptURL = tempDirectory.appendingPathComponent("write.py")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let (output, exitCode) = try CompressionTestHelpers.runCLICommand(
            Self.python3Path!,
            arguments: [scriptURL.path, zipURL.path, password]
        )
        XCTAssertEqual(exitCode, 0, "pyzipper failed to write: \(output)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        let entries = try EncryptedZIPReader.listEntries(at: zipURL)
        XCTAssertEqual(entries.map(\.path), ["hello.txt"])

        let extracted = try EncryptedZIPReader.extractEntry(path: "hello.txt", from: zipURL, password: password)
        XCTAssertEqual(String(data: extracted, encoding: .utf8), "written by pyzipper")
    }

    func testCompressionManager_RoutesToEncryptedWriterWhenPasswordProvided() async throws {
        let compressionManager = await CompressionManager()
        let fileURL = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "secret.txt", content: "via CompressionManager")
        let zipURL = tempDirectory.appendingPathComponent("via_manager.zip")

        _ = try await compressionManager.compress(
            fileMappings: [(url: fileURL, archivePath: "secret.txt")],
            to: zipURL,
            format: .zip,
            password: "pw123",
            progress: { _ in }
        )

        // A plain ZIPFoundation-based read should NOT be able to enumerate the encrypted entry
        // (ZIPFoundation skips encrypted entries entirely), confirming this really did produce
        // an AE-2 archive rather than a normal one.
        let plainEntries = try await ZIPCompressor.listEntries(at: zipURL)
        XCTAssertTrue(plainEntries.isEmpty)

        let extracted = try EncryptedZIPReader.extractEntry(path: "secret.txt", from: zipURL, password: "pw123")
        XCTAssertEqual(String(data: extracted, encoding: .utf8), "via CompressionManager")
    }
}
