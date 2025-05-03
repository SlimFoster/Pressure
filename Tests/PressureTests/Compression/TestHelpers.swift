import Foundation
import XCTest

class CompressionTestHelpers {
    static func createTempDirectory() -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PressureTests-\(UUID().uuidString)")
        
        try? FileManager.default.createDirectory(
            at: tempDirectory,
            withIntermediateDirectories: true
        )
        
        return tempDirectory
    }
    
    static func createTestFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
    
    static func createTestFiles(in directory: URL, count: Int) throws -> [URL] {
        var files: [URL] = []
        for i in 1...count {
            let content = "Test file \(i) content\nLine 2\nLine 3"
            let file = try createTestFile(in: directory, name: "test\(i).txt", content: content)
            files.append(file)
        }
        return files
    }
    
    static func createEmptyFile(in directory: URL, name: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try Data().write(to: fileURL)
        return fileURL
    }
    
    static func createLargeFile(in directory: URL, name: String, sizeInMB: Int = 1) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        let data = Data(count: sizeInMB * 1024 * 1024)
        try data.write(to: fileURL)
        return fileURL
    }
    
    static func createFileWithSpecialCharacters(in directory: URL, name: String) throws -> URL {
        let content = "File with special chars: àáâãäå"
        return try createTestFile(in: directory, name: name, content: content)
    }
    
    static func createNestedDirectoryStructure(in directory: URL) throws -> [URL] {
        let subDir1 = directory.appendingPathComponent("subdir1")
        let subDir2 = directory.appendingPathComponent("subdir2")
        try FileManager.default.createDirectory(at: subDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: subDir2, withIntermediateDirectories: true)
        
        let file1 = try createTestFile(in: subDir1, name: "file1.txt", content: "Content 1")
        let file2 = try createTestFile(in: subDir2, name: "file2.txt", content: "Content 2")
        let rootFile = try createTestFile(in: directory, name: "root.txt", content: "Root content")
        
        return [file1, file2, rootFile]
    }
    
    static func readFileContent(at url: URL) throws -> String {
        return try String(contentsOf: url, encoding: .utf8)
    }
    
    static func verifyFileExists(at url: URL) -> Bool {
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    static func getFileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return attributes[.size] as? Int64 ?? 0
    }
    
    static func createCorruptedArchive(at url: URL) throws {
        // Create a file that looks like an archive but is corrupted
        let corruptedData = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])
        try corruptedData.write(to: url)
    }
}
