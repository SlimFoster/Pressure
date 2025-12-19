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
    
    // MARK: - CLI Verification Helpers
    
    static func checkCLIToolAvailable(_ tool: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [tool]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    
    static func runCLICommand(_ command: String, arguments: [String], workingDirectory: URL? = nil) throws -> (output: String, exitCode: Int32) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments
        
        if let workingDirectory = workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""
        
        return (output: output, exitCode: process.terminationStatus)
    }
    
    static func verifyZipWithCLI(archiveURL: URL, extractTo: URL, expectedFiles: [String]) throws -> Bool {
        guard checkCLIToolAvailable("unzip") else {
            throw XCTSkip("unzip command not available")
        }
        
        // Extract using unzip
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/unzip",
            arguments: ["-q", "-o", archiveURL.path, "-d", extractTo.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify expected files exist
        for fileName in expectedFiles {
            let fileURL = extractTo.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                // Try without path component (unzip may extract to root)
                let justName = (fileName as NSString).lastPathComponent
                let altURL = extractTo.appendingPathComponent(justName)
                if !FileManager.default.fileExists(atPath: altURL.path) {
                    return false
                }
            }
        }
        
        return true
    }
    
    static func verifyGzipWithCLI(archiveURL: URL, extractTo: URL, expectedFileName: String) throws -> Bool {
        guard checkCLIToolAvailable("gunzip") else {
            throw XCTSkip("gunzip command not available")
        }
        
        // Copy archive to extract directory for decompression
        let tempArchive = extractTo.appendingPathComponent(archiveURL.lastPathComponent)
        try FileManager.default.copyItem(at: archiveURL, to: tempArchive)
        
        // Decompress using gunzip
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/gunzip",
            arguments: ["-f", tempArchive.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify decompressed file exists
        let decompressedName = archiveURL.deletingPathExtension().lastPathComponent
        let decompressedURL = extractTo.appendingPathComponent(decompressedName)
        return FileManager.default.fileExists(atPath: decompressedURL.path)
    }
    
    static func verifyTarWithCLI(archiveURL: URL, extractTo: URL, expectedFiles: [String]) throws -> Bool {
        guard checkCLIToolAvailable("tar") else {
            throw XCTSkip("tar command not available")
        }
        
        // Extract using tar
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/tar",
            arguments: ["-xf", archiveURL.path, "-C", extractTo.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify expected files exist
        for fileName in expectedFiles {
            let fileURL = extractTo.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                // Try without path component
                let justName = (fileName as NSString).lastPathComponent
                let altURL = extractTo.appendingPathComponent(justName)
                if !FileManager.default.fileExists(atPath: altURL.path) {
                    return false
                }
            }
        }
        
        return true
    }
    
    static func verifyBzip2WithCLI(archiveURL: URL, extractTo: URL, expectedFileName: String) throws -> Bool {
        guard checkCLIToolAvailable("bunzip2") else {
            throw XCTSkip("bunzip2 command not available")
        }
        
        // Copy archive to extract directory for decompression
        let tempArchive = extractTo.appendingPathComponent(archiveURL.lastPathComponent)
        try FileManager.default.copyItem(at: archiveURL, to: tempArchive)
        
        // Decompress using bunzip2
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/bunzip2",
            arguments: ["-f", tempArchive.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify decompressed file exists
        let decompressedName = archiveURL.deletingPathExtension().lastPathComponent
        let decompressedURL = extractTo.appendingPathComponent(decompressedName)
        return FileManager.default.fileExists(atPath: decompressedURL.path)
    }
    
    static func verifyTarGzWithCLI(archiveURL: URL, extractTo: URL, expectedFiles: [String]) throws -> Bool {
        guard checkCLIToolAvailable("tar") else {
            throw XCTSkip("tar command not available")
        }
        
        // Extract using tar (handles .tar.gz automatically)
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/tar",
            arguments: ["-xzf", archiveURL.path, "-C", extractTo.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify expected files exist
        for fileName in expectedFiles {
            let fileURL = extractTo.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let justName = (fileName as NSString).lastPathComponent
                let altURL = extractTo.appendingPathComponent(justName)
                if !FileManager.default.fileExists(atPath: altURL.path) {
                    return false
                }
            }
        }
        
        return true
    }
    
    static func verifyTarBz2WithCLI(archiveURL: URL, extractTo: URL, expectedFiles: [String]) throws -> Bool {
        guard checkCLIToolAvailable("tar") else {
            throw XCTSkip("tar command not available")
        }
        
        // Extract using tar (handles .tar.bz2 automatically)
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/tar",
            arguments: ["-xjf", archiveURL.path, "-C", extractTo.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify expected files exist
        for fileName in expectedFiles {
            let fileURL = extractTo.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                let justName = (fileName as NSString).lastPathComponent
                let altURL = extractTo.appendingPathComponent(justName)
                if !FileManager.default.fileExists(atPath: altURL.path) {
                    return false
                }
            }
        }
        
        return true
    }
    
    static func verifyZWithCLI(archiveURL: URL, extractTo: URL, expectedFileName: String) throws -> Bool {
        guard checkCLIToolAvailable("uncompress") else {
            throw XCTSkip("uncompress command not available")
        }
        
        // Copy archive to extract directory for decompression
        let tempArchive = extractTo.appendingPathComponent(archiveURL.lastPathComponent)
        try FileManager.default.copyItem(at: archiveURL, to: tempArchive)
        
        // Decompress using uncompress
        let (_, exitCode) = try runCLICommand(
            "/usr/bin/uncompress",
            arguments: ["-f", tempArchive.path],
            workingDirectory: nil
        )
        
        guard exitCode == 0 else {
            return false
        }
        
        // Verify decompressed file exists
        let decompressedName = archiveURL.deletingPathExtension().lastPathComponent
        let decompressedURL = extractTo.appendingPathComponent(decompressedName)
        return FileManager.default.fileExists(atPath: decompressedURL.path)
    }
}
