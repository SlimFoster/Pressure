import Foundation
import SWCompression

enum EncryptedZIPWriter {
    private static let versionNeededToExtract: UInt16 = 51 // required minimum for AE-x per APPNOTE
    private static let versionMadeBy: UInt16 = (3 << 8) | 63 // host: Unix: spec version 6.3

    static func compress(
        fileMappings: [(url: URL, archivePath: String)],
        outputURL: URL,
        password: String,
        keySize: AESKeySize = .aes256,
        progress: @escaping (Double) async -> Void
    ) async throws -> URL {
        guard !fileMappings.isEmpty else {
            throw CompressionError.invalidInput("No files to compress")
        }

        return try await Task.detached(priority: .userInitiated) {
            var archiveData = Data()
            var centralDirectory = Data()
            var entryCount = 0

            for (index, mapping) in fileMappings.enumerated() {
                let originalData = try Data(contentsOf: mapping.url)
                let compressedPayload = Deflate.compress(data: originalData)
                let modDate = (try? FileManager.default.attributesOfItem(atPath: mapping.url.path)[.modificationDate] as? Date) ?? Date()

                let salt = try AESEncryption.randomSalt(length: keySize.saltLength)
                let derived = try AESEncryption.deriveKeys(password: password, salt: salt, keySize: keySize)
                let ciphertext = try AESEncryption.transformCTR(data: compressedPayload, key: derived.encryptionKey)
                let authCode = AESEncryption.authenticationCode(ciphertext: ciphertext, authenticationKey: derived.authenticationKey)

                let entryData = salt + derived.passwordVerification + ciphertext + authCode
                let (dosTime, dosDate) = DOSDateTime.encode(modDate)
                let nameBytes = Array(mapping.archivePath.utf8)
                let extraField = AEExtraField(keySize: keySize, actualCompressionMethod: ZIPCompressionMethod.deflate).encoded()

                let localHeaderOffset = UInt32(archiveData.count)

                var localHeader = Data()
                localHeader.appendLE(ZIPSignature.localFileHeader)
                localHeader.appendLE(versionNeededToExtract)
                localHeader.appendLE(zipGeneralPurposeEncryptedFlag)
                localHeader.appendLE(ZIPCompressionMethod.aesEncrypted)
                localHeader.appendLE(dosTime)
                localHeader.appendLE(dosDate)
                localHeader.appendLE(UInt32(0)) // CRC-32: not stored for AE-2, HMAC covers integrity
                localHeader.appendLE(UInt32(entryData.count))
                localHeader.appendLE(UInt32(originalData.count))
                localHeader.appendLE(UInt16(nameBytes.count))
                localHeader.appendLE(UInt16(extraField.count))
                localHeader.append(contentsOf: nameBytes)
                localHeader.append(extraField)

                archiveData.append(localHeader)
                archiveData.append(entryData)

                var centralHeader = Data()
                centralHeader.appendLE(ZIPSignature.centralDirectoryHeader)
                centralHeader.appendLE(versionMadeBy)
                centralHeader.appendLE(versionNeededToExtract)
                centralHeader.appendLE(zipGeneralPurposeEncryptedFlag)
                centralHeader.appendLE(ZIPCompressionMethod.aesEncrypted)
                centralHeader.appendLE(dosTime)
                centralHeader.appendLE(dosDate)
                centralHeader.appendLE(UInt32(0)) // CRC-32
                centralHeader.appendLE(UInt32(entryData.count))
                centralHeader.appendLE(UInt32(originalData.count))
                centralHeader.appendLE(UInt16(nameBytes.count))
                centralHeader.appendLE(UInt16(extraField.count))
                centralHeader.appendLE(UInt16(0)) // file comment length
                centralHeader.appendLE(UInt16(0)) // disk number start
                centralHeader.appendLE(UInt16(0)) // internal file attributes
                centralHeader.appendLE(UInt32(0)) // external file attributes
                centralHeader.appendLE(localHeaderOffset)
                centralHeader.append(contentsOf: nameBytes)
                centralHeader.append(extraField)

                centralDirectory.append(centralHeader)
                entryCount += 1

                let currentIndex = index
                Task { @MainActor in
                    await progress(Double(currentIndex + 1) / Double(fileMappings.count))
                }
            }

            let centralDirectoryOffset = UInt32(archiveData.count)
            archiveData.append(centralDirectory)

            var eocd = Data()
            eocd.appendLE(ZIPSignature.endOfCentralDirectory)
            eocd.appendLE(UInt16(0)) // number of this disk
            eocd.appendLE(UInt16(0)) // disk where central directory starts
            eocd.appendLE(UInt16(entryCount))
            eocd.appendLE(UInt16(entryCount))
            eocd.appendLE(UInt32(centralDirectory.count))
            eocd.appendLE(centralDirectoryOffset)
            eocd.appendLE(UInt16(0)) // comment length
            archiveData.append(eocd)

            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            try archiveData.write(to: outputURL)

            return outputURL
        }.value
    }
}
