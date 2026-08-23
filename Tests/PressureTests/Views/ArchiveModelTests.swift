import XCTest
import Security
@testable import Pressure

@MainActor
final class ArchiveModelTests: XCTestCase {
    var tempDirectory: URL!
    var compressionManager: CompressionManager!
    var archiveModel: ArchiveModel!

    override func setUp() {
        super.setUp()
        tempDirectory = CompressionTestHelpers.createTempDirectory()
        compressionManager = CompressionManager()
        archiveModel = ArchiveModel(compressionManager: compressionManager)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        tempDirectory = nil
        compressionManager = nil
        archiveModel = nil
        super.tearDown()
    }

    func testLoadArchive_ZIP_PopulatesPackedSizeAndRatioWithoutExtraction() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        // Highly compressible content so deflate reliably shrinks it.
        let content = String(repeating: "The quick brown fox jumps over the lazy dog. ", count: 500)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "compressible.txt", content: content)
        let originalSize = try CompressionTestHelpers.getFileSize(at: fileURL)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: zipURL, progress: { _ in })

        try await archiveModel.loadArchive(from: zipURL)

        let item = try XCTUnwrap(archiveModel.items.first { $0.name == "compressible.txt" })
        XCTAssertEqual(item.size, originalSize)
        let packedSize = try XCTUnwrap(item.packedSize)
        XCTAssertGreaterThan(packedSize, 0)
        XCTAssertLessThan(packedSize, originalSize, "Highly repetitive content should compress smaller")
        let ratio = try XCTUnwrap(item.ratio)
        XCTAssertGreaterThan(ratio, 0)
        XCTAssertLessThan(ratio, 1)
    }

    func testArchiveStats_AggregatesAcrossItems() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let files = try CompressionTestHelpers.createTestFiles(in: sourceDir, count: 3)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: files, outputURL: zipURL, progress: { _ in })

        try await archiveModel.loadArchive(from: zipURL)

        let stats = archiveModel.archiveStats
        XCTAssertEqual(stats.itemCount, 3)
        XCTAssertGreaterThan(stats.originalSize, 0)
        XCTAssertGreaterThan(stats.packedSize, 0)
        XCTAssertNotNil(stats.savedPercent)
    }

    func testExtractedURL_LazilyExtractsSingleEntryWithMatchingContent() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "note.txt", content: "hello lazy extraction")

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: zipURL, progress: { _ in })

        try await archiveModel.loadArchive(from: zipURL)
        let item = try XCTUnwrap(archiveModel.items.first { $0.name == "note.txt" })

        let extractedURL = try await archiveModel.extractedURL(for: item)
        let extractedContent = try CompressionTestHelpers.readFileContent(at: extractedURL)
        XCTAssertEqual(extractedContent, "hello lazy extraction")

        // Second call should reuse the cached extraction rather than re-extracting.
        let secondURL = try await archiveModel.extractedURL(for: item)
        XCTAssertEqual(extractedURL, secondURL)
    }

    func testGetFilePathsForCompression_ResolvesArchiveEntriesLazily() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let files = try CompressionTestHelpers.createTestFiles(in: sourceDir, count: 2)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: files, outputURL: zipURL, progress: { _ in })

        try await archiveModel.loadArchive(from: zipURL)

        let resolved = try await archiveModel.getFilePathsForCompression()
        XCTAssertEqual(resolved.count, 2)
        for entry in resolved {
            XCTAssertTrue(FileManager.default.fileExists(atPath: entry.url.path))
        }
    }

    // MARK: - Live editing (commit/delete/rename/extractAll)

    func testCommit_PreservesNestedFolderStructureOnDisk() async throws {
        // Regression test for the flat-filename bug: compress() used to always use
        // lastPathComponent as the entry name, silently discarding folder structure.
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "guidelines.pdf", content: "brand guidelines")

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.addFileToArchive(fileURL, at: "Brand")
        try await archiveModel.commit()

        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        let reloaded = ArchiveModel(compressionManager: compressionManager)
        try await reloaded.loadArchive(from: zipURL)
        let item = try XCTUnwrap(reloaded.items.first { $0.name == "guidelines.pdf" })
        XCTAssertEqual(item.path, "Brand/guidelines.pdf")
    }

    func testDeleteItems_RemovesFileFromDiskAfterCommit() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let files = try CompressionTestHelpers.createTestFiles(in: sourceDir, count: 2)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: files, outputURL: zipURL, progress: { _ in })
        try await archiveModel.loadArchive(from: zipURL)

        let toDelete = try XCTUnwrap(archiveModel.items.first { $0.name == "test1.txt" })
        try await archiveModel.deleteItems(paths: [toDelete.path])

        XCTAssertFalse(archiveModel.items.contains { $0.name == "test1.txt" })

        let reloaded = ArchiveModel(compressionManager: compressionManager)
        try await reloaded.loadArchive(from: zipURL)
        XCTAssertFalse(reloaded.items.contains { $0.name == "test1.txt" })
        XCTAssertTrue(reloaded.items.contains { $0.name == "test2.txt" })
    }

    func testDeleteItems_RemovesArchiveEntirelyWhenLastFileDeleted() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "only.txt", content: "solo")

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: zipURL, progress: { _ in })
        try await archiveModel.loadArchive(from: zipURL)

        let item = try XCTUnwrap(archiveModel.items.first { $0.name == "only.txt" })
        try await archiveModel.deleteItems(paths: [item.path])

        XCTAssertFalse(FileManager.default.fileExists(atPath: zipURL.path))
    }

    func testRenameItem_File_UpdatesPathAndPreservesContentOnDisk() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "old.txt", content: "rename me")

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        _ = try await ZIPCompressor.compress(files: [fileURL], outputURL: zipURL, progress: { _ in })
        try await archiveModel.loadArchive(from: zipURL)

        try await archiveModel.renameItem(path: "old.txt", to: "new.txt")

        XCTAssertTrue(archiveModel.items.contains { $0.path == "new.txt" })
        XCTAssertFalse(archiveModel.items.contains { $0.path == "old.txt" })

        let reloaded = ArchiveModel(compressionManager: compressionManager)
        try await reloaded.loadArchive(from: zipURL)
        let renamedItem = try XCTUnwrap(reloaded.items.first { $0.path == "new.txt" })
        let content = try CompressionTestHelpers.readFileContent(at: try await reloaded.extractedURL(for: renamedItem))
        XCTAssertEqual(content, "rename me")
    }

    func testRenameItem_Directory_RemapsDescendantPaths() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "logo.svg", content: "svg data")

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.addFileToArchive(fileURL, at: "Brand")
        try await archiveModel.commit()

        try await archiveModel.renameItem(path: "Brand", to: "BrandAssets")

        XCTAssertTrue(archiveModel.items.contains { $0.path == "BrandAssets" && $0.isDirectory })
        XCTAssertTrue(archiveModel.items.contains { $0.path == "BrandAssets/logo.svg" })
        XCTAssertFalse(archiveModel.items.contains { $0.path.hasPrefix("Brand/") })

        let reloaded = ArchiveModel(compressionManager: compressionManager)
        try await reloaded.loadArchive(from: zipURL)
        XCTAssertTrue(reloaded.items.contains { $0.path == "BrandAssets/logo.svg" })
    }

    func testExtractAll_PreservesFolderStructureAndContent() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "notes.txt", content: "extract me")

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.addFileToArchive(fileURL, at: "Docs")
        try await archiveModel.commit()

        try await archiveModel.loadArchive(from: zipURL)

        let destination = tempDirectory.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try await archiveModel.extractAll(to: destination)

        let extractedFile = destination.appendingPathComponent("Docs/notes.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: extractedFile.path))
        XCTAssertEqual(try CompressionTestHelpers.readFileContent(at: extractedFile), "extract me")
    }

    // MARK: - Encryption

    func testCommit_WithPassword_WritesRealEncryptedArchive() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "secret.txt", content: "classified")

        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.password = "s3cr3t"
        archiveModel.addFileToArchive(fileURL, at: "")
        try await archiveModel.commit()

        // A plain (non-encryption-aware) reader should see no entries — proves this really is
        // an AE-2 archive, not a normal zip that happens to have a password field ignored.
        let plainEntries = try await ZIPCompressor.listEntries(at: zipURL)
        XCTAssertTrue(plainEntries.isEmpty)

        XCTAssertTrue(EncryptedZIPReader.isEncryptedZIP(at: zipURL))
    }

    func testLoadArchive_Encrypted_RequiresPassword() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "secret.txt", content: "classified")
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        _ = try await EncryptedZIPWriter.compress(
            fileMappings: [(url: fileURL, archivePath: "secret.txt")],
            outputURL: zipURL,
            password: "correct-password",
            progress: { _ in }
        )

        do {
            try await archiveModel.loadArchive(from: zipURL)
            XCTFail("Expected incorrectPassword when no password is given for an encrypted archive")
        } catch CompressionError.incorrectPassword {
            // expected
        }

        do {
            try await archiveModel.loadArchive(from: zipURL, password: "wrong-password")
            XCTFail("Expected incorrectPassword for a wrong password")
        } catch CompressionError.incorrectPassword {
            // expected
        }

        try await archiveModel.loadArchive(from: zipURL, password: "correct-password")
        XCTAssertEqual(archiveModel.items.map(\.name), ["secret.txt"])

        let item = try XCTUnwrap(archiveModel.items.first)
        let extractedURL = try await archiveModel.extractedURL(for: item)
        XCTAssertEqual(try CompressionTestHelpers.readFileContent(at: extractedURL), "classified")
    }

    func testRenameItem_OnEncryptedArchive_StaysEncryptedAfterCommit() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = try CompressionTestHelpers.createTestFile(in: sourceDir, name: "old.txt", content: "rename me")
        let zipURL = tempDirectory.appendingPathComponent("encrypted.zip")

        archiveModel.archiveURL = zipURL
        archiveModel.password = "pw"
        archiveModel.addFileToArchive(fileURL, at: "")
        try await archiveModel.commit()

        try await archiveModel.renameItem(path: "old.txt", to: "new.txt")

        let reloaded = ArchiveModel(compressionManager: compressionManager)
        try await reloaded.loadArchive(from: zipURL, password: "pw")
        XCTAssertEqual(reloaded.items.map(\.path), ["new.txt"])
    }

    // MARK: - Splitting

    func testCommit_WithSplitVolumeSize_ProducesRealVolumesAndBrowsingKeepsWorking() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("data.bin")
        try randomData(count: 200_000).write(to: fileURL)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.splitVolumeSize = 65536
        archiveModel.addFileToArchive(fileURL, at: "")
        try await archiveModel.commit()

        // Real volumes on disk, not one plain file.
        let directoryContents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
        let volumeNames = directoryContents.map(\.lastPathComponent).filter { $0.hasPrefix("archive.z") || $0 == "archive.zip" }
        XCTAssertGreaterThan(volumeNames.count, 1)
        XCTAssertTrue(volumeNames.contains("archive.zip"))

        // But browsing/extraction still works normally, via the internal working copy.
        XCTAssertEqual(archiveModel.items.map(\.name), ["data.bin"])
        let item = try XCTUnwrap(archiveModel.items.first)
        let extractedURL = try await archiveModel.extractedURL(for: item)
        XCTAssertEqual(try Data(contentsOf: extractedURL), try Data(contentsOf: fileURL))
    }

    func testCommit_TogglingSplitOff_CleansUpVolumesAndRestoresPlainFile() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("data.bin")
        try randomData(count: 200_000).write(to: fileURL)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.splitVolumeSize = 65536
        archiveModel.addFileToArchive(fileURL, at: "")
        try await archiveModel.commit()

        archiveModel.splitVolumeSize = nil
        try await archiveModel.commit()

        let directoryContents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
        let volumeNames = directoryContents.map(\.lastPathComponent).filter { $0.hasPrefix("archive.z0") }
        XCTAssertEqual(volumeNames, [], "Stale split volumes should be cleaned up after switching split off")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zipURL.path))

        let reloaded = ArchiveModel(compressionManager: compressionManager)
        try await reloaded.loadArchive(from: zipURL)
        XCTAssertEqual(reloaded.items.map(\.name), ["data.bin"])
    }

    func testCommit_SplitAndEncryptedTogether() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let fileURL = sourceDir.appendingPathComponent("data.bin")
        try randomData(count: 200_000).write(to: fileURL)

        let zipURL = tempDirectory.appendingPathComponent("archive.zip")
        archiveModel.archiveURL = zipURL
        archiveModel.password = "pw"
        archiveModel.splitVolumeSize = 65536
        archiveModel.addFileToArchive(fileURL, at: "")
        try await archiveModel.commit()

        let directoryContents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
        let volumeNames = directoryContents.map(\.lastPathComponent).filter { $0.hasPrefix("archive.z") || $0 == "archive.zip" }
        XCTAssertGreaterThan(volumeNames.count, 1)

        // Rejoin the real volumes and confirm the result is genuinely AE-2 encrypted.
        let rejoinedURL = tempDirectory.appendingPathComponent("rejoined.zip")
        try compressionManager.rejoinSplit(startingFrom: zipURL, to: rejoinedURL)
        XCTAssertTrue(EncryptedZIPReader.isEncryptedZIP(at: rejoinedURL))
        let extracted = try EncryptedZIPReader.extractEntry(path: "data.bin", from: rejoinedURL, password: "pw")
        XCTAssertEqual(extracted, try Data(contentsOf: fileURL))
    }

    func testCommit_TAR_WithSplitVolumeSize_UsesGenericChunking() async throws {
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let files = try CompressionTestHelpers.createTestFiles(in: sourceDir, count: 3)

        let tarURL = tempDirectory.appendingPathComponent("archive.tar")
        archiveModel.archiveURL = tarURL
        archiveModel.splitVolumeSize = 512
        for file in files {
            archiveModel.addFileToArchive(file, at: "")
        }
        try await archiveModel.commit()

        let directoryContents = try FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil)
        let partNames = directoryContents.map(\.lastPathComponent).filter { $0.hasPrefix("archive.tar.") }
        XCTAssertGreaterThan(partNames.count, 1)

        // Browsing still works via the internal working copy.
        XCTAssertEqual(Set(archiveModel.items.map(\.name)), Set(files.map(\.lastPathComponent)))
    }

    private func randomData(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else {
            throw CompressionError.invalidInput("Failed to generate random test data")
        }
        return Data(bytes)
    }
}
