import XCTest
@testable import Pressure

@MainActor
final class ZCompressorTests: XCTestCase {
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
    
    func testCompressToZ() async throws {
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Hello, World!")
        let outputURL = tempDirectory.appendingPathComponent("test.Z")
        
        let result = try await compressionManager.compress(
            files: [testFile],
            to: outputURL,
            format: .z,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
    
    func testDecompressZ() async throws {
        // First create a Z file
        let originalContent = "Test content for Z format"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "original.txt", content: originalContent)
        let zURL = tempDirectory.appendingPathComponent("test.Z")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: zURL,
            format: .z,
            progress: { _ in }
        )
        
        // Now decompress it
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: zURL,
            to: extractDir,
            progress: { _ in }
        )
        
        XCTAssertFalse(extractedFiles.isEmpty)
        // Verify content
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressDecompressZ_RoundTrip() async throws {
        let originalContent = "Z format round-trip test"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let zURL = tempDirectory.appendingPathComponent("test.Z")
        
        _ = try await compressionManager.compress(
            files: [testFile],
            to: zURL,
            format: .z,
            progress: { _ in }
        )
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let extractedFiles = try await compressionManager.decompress(
            file: zURL,
            to: extractDir,
            progress: { _ in }
        )
        
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFiles[0])
        XCTAssertEqual(extractedContent, originalContent)
    }
    
    func testCompressZ_OnlySupportsSingleFile() async throws {
        // Z format should only compress single files
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 2)
        let outputURL = tempDirectory.appendingPathComponent("multi.Z")
        
        // Should only compress the first file
        let result = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .z,
            progress: { _ in }
        )
        
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.path))
    }
}
