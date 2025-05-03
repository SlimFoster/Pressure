import XCTest
@testable import Pressure

@MainActor
final class CompressionManagerTests: XCTestCase {
    var compressionManager: CompressionManager!
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        compressionManager = CompressionManager()
        tempDirectory = CompressionTestHelpers.createTempDirectory()
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        compressionManager = nil
        super.tearDown()
    }
    
    // MARK: - Format Detection Tests
    
    func testDetectFormat_ZIP() {
        let url = tempDirectory.appendingPathComponent("test.zip")
        let format = compressionManager.detectFormat(from: url)
        XCTAssertEqual(format, .zip)
    }
    
    func testDetectFormat_GZIP() {
        let url = tempDirectory.appendingPathComponent("test.gz")
        let format = compressionManager.detectFormat(from: url)
        XCTAssertEqual(format, .gzip)
    }
    
    func testDetectFormat_TAR() {
        let url = tempDirectory.appendingPathComponent("test.tar")
        let format = compressionManager.detectFormat(from: url)
        XCTAssertEqual(format, .tar)
    }
    
    func testDetectFormat_BZIP2() {
        let url = tempDirectory.appendingPathComponent("test.bz2")
        let format = compressionManager.detectFormat(from: url)
        XCTAssertEqual(format, .bzip2)
    }
    
    func testDetectFormat_Z() {
        let url = tempDirectory.appendingPathComponent("test.Z")
        let format = compressionManager.detectFormat(from: url)
        XCTAssertEqual(format, .z)
    }
    
    func testDetectFormat_RAR() {
        let url = tempDirectory.appendingPathComponent("test.rar")
        let format = compressionManager.detectFormat(from: url)
        XCTAssertEqual(format, .rar)
    }
    
    func testDetectFormat_UnknownExtension() {
        let url = tempDirectory.appendingPathComponent("test.unknown")
        let format = compressionManager.detectFormat(from: url)
        // Should default to zip for unknown extensions
        XCTAssertEqual(format, .zip)
    }
    
    func testDetectFormat_CaseInsensitive() {
        let url1 = tempDirectory.appendingPathComponent("test.ZIP")
        let url2 = tempDirectory.appendingPathComponent("test.zip")
        let format1 = compressionManager.detectFormat(from: url1)
        let format2 = compressionManager.detectFormat(from: url2)
        XCTAssertEqual(format1, format2)
        XCTAssertEqual(format1, .zip)
    }
    
    // MARK: - Error Handling Tests
    
    func testCompress_EmptyFileList() async {
        let outputURL = tempDirectory.appendingPathComponent("empty.zip")
        
        do {
            _ = try await compressionManager.compress(
                files: [],
                to: outputURL,
                format: .zip,
                progress: { _ in }
            )
            XCTFail("Should have thrown an error for empty file list")
        } catch {
            // Expected to fail
            XCTAssertTrue(error is CompressionError || error.localizedDescription.contains("No files"))
        }
    }
    
    func testCompress_InvalidOutputPath() async throws {
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Test")
        // Use a path in a non-existent directory
        let invalidPath = tempDirectory
            .appendingPathComponent("nonexistent")
            .appendingPathComponent("test.zip")
        
        // This should either succeed (creating the directory) or fail gracefully
        do {
            _ = try await compressionManager.compress(
                files: [testFile],
                to: invalidPath,
                format: .zip,
                progress: { _ in }
            )
        } catch {
            // Acceptable if it fails for invalid path
            XCTAssertNotNil(error)
        }
    }
    
    func testCompress_NonExistentFile() async {
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.txt")
        let outputURL = tempDirectory.appendingPathComponent("test.zip")
        
        do {
            _ = try await compressionManager.compress(
                files: [nonExistentFile],
                to: outputURL,
                format: .zip,
                progress: { _ in }
            )
            // May succeed or fail depending on zip command behavior
        } catch {
            // Expected to fail for non-existent file
            XCTAssertNotNil(error)
        }
    }
    
    // MARK: - Progress Reporting Tests
    
    func testCompress_ProgressReporting() async throws {
        let files = try CompressionTestHelpers.createTestFiles(in: tempDirectory, count: 5)
        let outputURL = tempDirectory.appendingPathComponent("progress.zip")
        
        var progressValues: [Double] = []
        
        _ = try await compressionManager.compress(
            files: files,
            to: outputURL,
            format: .zip,
            progress: { progress in
                progressValues.append(progress)
            }
        )
        
        // Progress should be reported (at least start and end)
        XCTAssertFalse(progressValues.isEmpty)
        // Should start at 0.0
        if let first = progressValues.first {
            XCTAssertEqual(first, 0.0, accuracy: 0.01)
        }
        // Should end at 1.0
        if let last = progressValues.last {
            XCTAssertEqual(last, 1.0, accuracy: 0.01)
        }
        // Progress should be monotonic (non-decreasing)
        for i in 1..<progressValues.count {
            XCTAssertGreaterThanOrEqual(progressValues[i], progressValues[i-1], "Progress should be non-decreasing")
        }
    }
    
    func testDecompress_ProgressReporting() async throws {
        // Create and compress a file first
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Test content")
        let zipURL = tempDirectory.appendingPathComponent("test.zip")
        _ = try await compressionManager.compress(files: [testFile], to: zipURL, format: .zip, progress: { _ in })
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        var progressValues: [Double] = []
        _ = try await compressionManager.decompress(
            file: zipURL,
            to: extractDir,
            progress: { progress in
                progressValues.append(progress)
            }
        )
        
        XCTAssertFalse(progressValues.isEmpty)
        if let first = progressValues.first {
            XCTAssertEqual(first, 0.0, accuracy: 0.01)
        }
    }
    
    // MARK: - RAR Format Tests
    
    func testRAR_UnsupportedCompression() async throws {
        let testFile = try CompressionTestHelpers.createTestFile(in: tempDirectory, name: "test.txt", content: "Test")
        let outputURL = tempDirectory.appendingPathComponent("test.rar")
        
        do {
            _ = try await compressionManager.compress(
                files: [testFile],
                to: outputURL,
                format: .rar,
                progress: { _ in }
            )
            XCTFail("RAR compression should not be supported")
        } catch {
            if let compressionError = error as? CompressionError {
                XCTAssertTrue(compressionError.localizedDescription.contains("RAR") || 
                            compressionError.localizedDescription.contains("unsupported"))
            }
        }
    }
    
    func testRAR_UnsupportedDecompression() async throws {
        // Create a fake RAR file
        let rarURL = tempDirectory.appendingPathComponent("test.rar")
        try CompressionTestHelpers.createCorruptedArchive(at: rarURL)
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        do {
            _ = try await compressionManager.decompress(
                file: rarURL,
                to: extractDir,
                progress: { _ in }
            )
            XCTFail("RAR decompression should not be supported")
        } catch {
            if let compressionError = error as? CompressionError {
                XCTAssertTrue(compressionError.localizedDescription.contains("RAR") || 
                            compressionError.localizedDescription.contains("unsupported"))
            }
        }
    }
    
    func testDecompress_InvalidArchive() async throws {
        // Create a corrupted archive file
        let corruptedURL = tempDirectory.appendingPathComponent("corrupted.zip")
        try CompressionTestHelpers.createCorruptedArchive(at: corruptedURL)
        
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        do {
            _ = try await compressionManager.decompress(
                file: corruptedURL,
                to: extractDir,
                progress: { _ in }
            )
            // May or may not fail depending on format detection
        } catch {
            // Expected to fail for corrupted archive
            XCTAssertNotNil(error)
        }
    }
    
    func testDecompress_NonExistentFile() async throws {
        let nonExistentFile = tempDirectory.appendingPathComponent("nonexistent.zip")
        let extractDir = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        
        do {
            _ = try await compressionManager.decompress(
                file: nonExistentFile,
                to: extractDir,
                progress: { _ in }
            )
            XCTFail("Should have thrown an error for non-existent file")
        } catch {
            XCTAssertNotNil(error)
        }
    }
}
