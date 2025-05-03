import XCTest
@testable import Pressure

@MainActor
final class ZIPCompressorTests: XCTestCase {
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
    
    func testCompressToZip_SingleFile() async throws {
        // Create a test file
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Hello, World!")
        let outputURL = tempDirectory.appendingPathComponent("test.zip")
        
        // Compress using public API
        let result = try await compressionManager.compress(
            files: [testFile],
            to: outputURL,
            format: .zip,
            progress: { _ in }
        )
        
        // Verify archive was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        XCTAssertGreaterThan(try FileManager.default.attributesOfItem(atPath: result.path)[.size] as! Int64, 0)
    }
    
    func testCompressToZip_MultipleFiles() async throws {
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 3)
        let outputURL = tempDirectory.appendingPathComponent("multi.zip")
        
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .zip,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testDecompressZip() async throws {
        // First create a zip file
        let originalContent = "Test content for round-trip verification"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "original.txt", content: originalContent)
        let zipURL = tempDirectory.appendingPathComponent("test.zip")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: zipURL,
            format: .zip,
            progress: { _ in }
        )
        
        // Now decompress it using public API
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: zipURL,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertFalse(extractedFiles.isEmpty)
        XCTAssertEqual(extractedFiles.count, 1)
        
        // Verify content matches original
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressDecompressZip_RoundTrip() async throws {
        let originalContent = "Round-trip test content\nWith multiple lines\nAnd special chars: àáâ"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "roundtrip.txt", content: originalContent)
        let zipURL = tempDirectory.appendingPathComponent("roundtrip.zip")
        
        // Compress
        _ = try await compressionManager.compress(
            files: [testFile],
            to: zipURL,
            format: .zip,
            progress: { _ in }
        )
        
        // Decompress
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: zipURL,
            to: extractDir,
            progress: { _ in }
        )
        
        // Verify
        XCTAssertEqual(extractedFiles.count, 1)
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent, "Round-trip compression should preserve content exactly")
    }
    
    func testCompressZip_WithEmptyFile() async throws {
        let emptyFile = try CompressionTestHelpers.createEmptyFile(in: tempDirectory, name: "empty.txt")
        let outputURL = tempDirectory.appendingPathComponent("empty.zip")
        
        let result = try await compressionManager.compress(
            files: [emptyFile],
            to: outputURL,
            format: .zip,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        
        // Should be able to decompress empty file
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: result,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertFalse(extractedFiles.isEmpty)
        let extractedSize = try CompressionTestHelpers.getFileSize(at: extractedFiles[0])
        XCTAssertEqual(extractedSize, 0)
    }
    
    func testCompressZip_WithSpecialCharacters() async throws {
        let specialFile = try CompressionTestHelpers.createFileWithSpecialCharacters(in: tempDirectory, name: "special_àáâ.txt")
        let outputURL = tempDirectory.appendingPathComponent("special.zip")
        
        let result = try await compressionManager.compress(
            files: [specialFile],
            to: outputURL,
            format: .zip,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testCompressZip_WithNestedDirectories() async throws {
        let files = try CompressionTestHelpers.createNestedDirectoryStructure(in: tempDirectory)
        let outputURL = tempDirectory.appendingPathComponent("nested.zip")
        
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .zip,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        
        // Verify decompression preserves structure
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: result,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertEqual(extractedFiles.count, 3)
    }
    
    func testCompressZip_FileSizeVerification() async throws {
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Hello, World!")
        let originalSize = try CompressionTestHelpers.getFileSize(at: testFile)
        let outputURL = tempDirectory.appendingPathComponent("test.zip")
        
        let result = try await compressionManager.compress(
            files: [testFile],
            to: outputURL,
            format: .zip,
            progress: { _ in }
        )
        
        let archiveSize = try CompressionTestHelpers.getFileSize(at: result)
        XCTAssertGreaterThan(archiveSize, 0)
        // Archive should typically be smaller than original (or at least not much larger)
        // But we allow some overhead for ZIP headers
        XCTAssertLessThanOrEqual(archiveSize, originalSize + 200)
    }
}
