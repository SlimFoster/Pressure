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
    
    func testCompressTar_VerifiedWithCLI() async throws {
        // Create test file
        let originalContent = "Test content for TAR CLI verification"
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: originalContent)
        let tarURL = tempDirectory.appendingPathComponent("test.tar")
        
        // Compress using app's compressor
        _ = try await compressionManager.compress(
            files: [testFile],
            to: tarURL,
            format: .tar,
            progress: { _ in }
        )
        
        // Verify archive was created
        XCTAssertTrue(FileManager.default.fileExists(atPath: tarURL.path))
        
        // Verify using CLI tar
        let extractDir = tempDirectory.appendingPathComponent("cli_extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let verified = try CompressionTestHelpers.verifyTarWithCLI(
            archiveURL: tarURL,
            extractTo: extractDir,
            expectedFiles: ["test.txt"]
        )
        
        XCTAssertTrue(verified, "TAR archive should be extractable with tar command")
        
        // Verify content matches
        let extractedFile = extractDir.appendingPathComponent("test.txt")
        if FileManager.default.fileExists(atPath: extractedFile.path) {
            let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedFile)
            XCTAssertEqual(extractedContent, originalContent, "Content should match after CLI extraction")
        }
    }
    
    func testCompressTar_MultipleFiles_VerifiedWithCLI() async throws {
        // Create multiple test files
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 3)
        let tarURL = tempDirectory.appendingPathComponent("multi.tar")
        
        // Compress using app's compressor
        _ = try await compressionManager.compress(
            files: files,
            to: tarURL,
            format: .tar,
            progress: { _ in }
        )
        
        // Verify using CLI tar
        let extractDir = tempDirectory.appendingPathComponent("cli_extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        let verified = try CompressionTestHelpers.verifyTarWithCLI(
            archiveURL: tarURL,
            extractTo: extractDir,
            expectedFiles: ["test1.txt", "test2.txt", "test3.txt"]
        )
        
        XCTAssertTrue(verified, "TAR archive with multiple files should be extractable with tar command")
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
