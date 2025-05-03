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
