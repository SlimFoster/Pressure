import XCTest
@testable import Pressure

@MainActor
final class TARCompressorTests: XCTestCase {
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
    
    func testCompressToTar() async throws {
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 2)
        let outputURL = tempDirectory.appendingPathComponent("test.tar")
        
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .tar,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testDecompressTar() async throws {
        // First create a tar file
        let originalContent = "Test content for TAR"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "original.txt", content: originalContent)
        let tarURL = tempDirectory.appendingPathComponent("test.tar")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: tarURL,
            format: .tar,
            progress: { _ in }
        )
        
        // Now decompress it
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: tarURL,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertFalse(extractedFiles.isEmpty)
        // Verify content
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressDecompressTar_RoundTrip() async throws {
        let originalContent = "TAR round-trip test content"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let tarURL = tempDirectory.appendingPathComponent("test.tar")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: tarURL,
            format: .tar,
            progress: { _ in }
        )
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: tarURL,
            to: extractDir,
            progress: { _ in }
        )
        
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressTar_MultipleFiles() async throws {
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 5)
        let outputURL = tempDirectory.appendingPathComponent("multi.tar")
        
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .tar,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
        
        // Verify all files are in the archive
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: result,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertEqual(extractedFiles.count, 5)
    }
}
