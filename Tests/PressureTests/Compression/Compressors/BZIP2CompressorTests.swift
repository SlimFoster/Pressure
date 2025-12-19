import XCTest
@testable import Pressure

@MainActor
final class BZIP2CompressorTests: XCTestCase {
    var compressionManager: CompressionManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        compressionManager = CompressionManager()
        tempDirectory = CompressionTestHelpers.createTempDirectory()
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        compressionManager = nil
        super.tearDown()
    }
    
    func testCompressToBzip2() async throws {
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Hello, World!")
        let outputURL = tempDirectory.appendingPathComponent("test.bz2")
        
        let result = try await compressionManager.compress(
            files: [testFile],
            to: outputURL,
            format: .bzip2,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testDecompressBzip2() async throws {
        // First create a bzip2 file
        let originalContent = "Test content for BZIP2"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "original.txt", content: originalContent)
        let bz2URL = tempDirectory.appendingPathComponent("test.bz2")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: bz2URL,
            format: .bzip2,
            progress: { _ in }
        )
        
        // Now decompress it
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: bz2URL,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertFalse(extractedFiles.isEmpty)
        // Verify content
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressBzip2_VerifiedWithCLI() async throws {
        // Create test file
        let originalContent = "Test content for BZIP2 CLI verification"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let bz2URL = tempDirectory.appendingPathComponent("test.bz2")
        
        // Compress using app's compressor
        _ = try await compressionManager.compress(
            files: [testFile],
            to: bz2URL,
            format: .bzip2,
            progress: { _ in }
        )
        
        // Verify archive was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: bz2URL.path))
        
        // Verify using CLI bunzip2
        let extractDir = tempDirectory.appendingPathComponent("cli_extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let verified = try CompressionTestHelpers.verifyBzip2WithCLI(
            archiveURL: bz2URL,
            extractTo: extractDir,
            expectedFileName: "test.txt"
        )
        
        XCTAssertTrue(verified, "BZIP2 archive should be extractable with bunzip2 command")
        
        // Verify content matches
        let extractedFile = extractDir.appendingPathComponent("test.txt")
        if FileManager.default.fileExists(atPath: extractedFile.path) {
            let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFile)
            XCTAssertEqual(extractedContent, originalContent, "Content should match after CLI extraction")
        }
    }
    
    func testCompressBzip2_MultipleFiles_VerifiedWithCLI() async throws {
        // BZIP2 with multiple files creates tar.bz2
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 3)
        let tarBz2URL = tempDirectory.appendingPathComponent("multi.tar.bz2")
        
        // Compress using app's compressor
        _ = try await compressionManager.compress(
            files: files,
            to: tarBz2URL,
            format: .bzip2,
            progress: { _ in }
        )
        
        // Verify using CLI tar
        let extractDir = tempDirectory.appendingPathComponent("cli_extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let verified = try CompressionTestHelpers.verifyTarBz2WithCLI(
            archiveURL: tarBz2URL,
            extractTo: extractDir,
            expectedFiles: ["test1.txt", "test2.txt", "test3.txt"]
        )
        
        XCTAssertTrue(verified, "tar.bz2 archive should be extractable with tar command")
    }
    
    func testCompressBzip2_MultipleFiles_CreatesTarBz2() async throws {
        // BZIP2 with multiple files should create a tar.bz2
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 3)
        let outputURL = tempDirectory.appendingPathComponent("multi.tar.bz2")
        
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .bzip2,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testCompressDecompressBzip2_RoundTrip() async throws {
        let originalContent = "BZIP2 round-trip test"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let bz2URL = tempDirectory.appendingPathComponent("test.bz2")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: bz2URL,
            format: .bzip2,
            progress: { _ in }
        )
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: bz2URL,
            to: extractDir,
            progress: { _ in }
        )
        
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
}
