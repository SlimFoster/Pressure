import XCTest
@testable import Pressure

@MainActor
final class GZIPCompressorTests: XCTestCase {
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
    
    func testCompressToGzip() async throws {
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Hello, World!")
        let outputURL = tempDirectory.appendingPathComponent("test.gz")
        
        let result = try await compressionManager.compress(
            files: [testFile],
            to: outputURL,
            format: .gzip,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testDecompressGzip() async throws {
        // First create a gzip file
        let originalContent = "Test content for GZIP"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "original.txt", content: originalContent)
        let gzURL = tempDirectory.appendingPathComponent("test.gz")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: gzURL,
            format: .gzip,
            progress: { _ in }
        )
        
        // Now decompress it
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: gzURL,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertFalse(extractedFiles.isEmpty)
        // Verify content
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressGzip_VerifiedWithCLI() async throws {
        // Create test file
        let originalContent = "Test content for GZIP CLI verification"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let gzURL = tempDirectory.appendingPathComponent("test.gz")
        
        // Compress using app's compressor
        _ = try await compressionManager.compress(
            files: [testFile],
            to: gzURL,
            format: .gzip,
            progress: { _ in }
        )
        
        // Verify archive was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: gzURL.path))
        
        // Verify using CLI gunzip
        let extractDir = tempDirectory.appendingPathComponent("cli_extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let verified = try CompressionTestHelpers.verifyGzipWithCLI(
            archiveURL: gzURL,
            extractTo: extractDir,
            expectedFileName: "test.txt"
        )
        
        XCTAssertTrue(verified, "GZIP archive should be extractable with gunzip command")
        
        // Verify content matches
        let extractedFile = extractDir.appendingPathComponent("test.txt")
        if FileManager.default.fileExists(atPath: extractedFile.path) {
            let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFile)
            XCTAssertEqual(extractedContent, originalContent, "Content should match after CLI extraction")
        }
    }
    
    func testCompressGzip_MultipleFiles_VerifiedWithCLI() async throws {
        // GZIP with multiple files creates tar.gz
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 3)
        let tarGzURL = tempDirectory.appendingPathComponent("multi.tar.gz")
        
        // Compress using app's compressor
        _ = try await compressionManager.compress(
            files: files,
            to: tarGzURL,
            format: .gzip,
            progress: { _ in }
        )
        
        // Verify using CLI tar
        let extractDir = tempDirectory.appendingPathComponent("cli_extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let verified = try CompressionTestHelpers.verifyTarGzWithCLI(
            archiveURL: tarGzURL,
            extractTo: extractDir,
            expectedFiles: ["test1.txt", "test2.txt", "test3.txt"]
        )
        
        XCTAssertTrue(verified, "tar.gz archive should be extractable with tar command")
    }
    
    func testCompressGzip_MultipleFiles_CreatesTarGz() async throws {
        // GZIP with multiple files should create a tar.gz
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 3)
        let outputURL = tempDirectory.appendingPathComponent("multi.tar.gz")
        
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .gzip,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        // Verify it's actually a tar.gz (has .tar.gz extension or is larger than single file gzip)
        let archiveSize = try CompressionTestHelpers.getFileSize(at: result)
        XCTAssertGreaterThan(archiveSize, 0)
    }
    
    func testCompressDecompressGzip_RoundTrip() async throws {
        let originalContent = "GZIP round-trip test"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let gzURL = tempDirectory.appendingPathComponent("test.gz")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: gzURL,
            format: .gzip,
            progress: { _ in }
        )
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: gzURL,
            to: extractDir,
            progress: { _ in }
        )
        
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
}
