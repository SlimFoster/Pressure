import Foundation
import SWCompression

struct EncryptedZIPEntryInfo {
    let path: String
    let uncompressedSize: Int64
    /// The deflated payload size, excluding the AE-2 wrapper overhead (salt/verify/HMAC) — this
    /// is the size figure comparable to a plain ZIP entry's `compressedSize`.
    let packedSize: Int64
    let modificationDate: Date?
}

enum EncryptedZIPReader {
    private struct CentralEntry {
        let path: String
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let localHeaderOffset: UInt32
        let modDate: Date
        let aeInfo: AEExtraField
    }

    static func isEncryptedZIP(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let eocdOffset = try? findEOCD(in: data),
              let entries = try? parseCentralDirectory(from: data, eocdOffset: eocdOffset) else {
            return false
        }
        return !entries.isEmpty
    }

    /// Cheaply checks a password against the archive's first entry using only the 2-byte
    /// password-verification value — no decryption or HMAC work needed. This is a fast way to
    /// give "wrong password" feedback when unlocking an archive; it is not by itself a strong
    /// guarantee (2 bytes), which is why `extractEntry` still does the full HMAC check before
    /// trusting any decrypted content.
    static func verifyPassword(at url: URL, password: String) throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let eocdOffset = try findEOCD(in: data)
        let entries = try parseCentralDirectory(from: data, eocdOffset: eocdOffset)

        guard let firstEntry = entries.first else {
            return // nothing to verify against; treat as accepted
        }

        let dataStart = try localFileDataOffset(for: firstEntry, in: data)
        let saltLength = firstEntry.aeInfo.keySize.saltLength
        let salt = data.subdata(in: dataStart..<(dataStart + saltLength))
        let storedVerification = data.subdata(in: (dataStart + saltLength)..<(dataStart + saltLength + 2))

        let derived = try AESEncryption.deriveKeys(password: password, salt: salt, keySize: firstEntry.aeInfo.keySize)
        guard derived.passwordVerification == storedVerification else {
            throw CompressionError.incorrectPassword
        }
    }

    static func listEntries(at url: URL) throws -> [EncryptedZIPEntryInfo] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let eocdOffset = try findEOCD(in: data)
        let entries = try parseCentralDirectory(from: data, eocdOffset: eocdOffset)

        return entries.map { entry in
            let overhead = entry.aeInfo.keySize.saltLength + 2 + 10
            let packedSize = max(0, Int(entry.compressedSize) - overhead)
            return EncryptedZIPEntryInfo(
                path: entry.path,
                uncompressedSize: Int64(entry.uncompressedSize),
                packedSize: Int64(packedSize),
                modificationDate: entry.modDate
            )
        }
    }

    /// Verifies the password against the entry's 2-byte check value before doing any real work —
    /// this is a fast, spec-provided way to reject a wrong password up front. It's not a strong
    /// guarantee on its own (2 bytes), which is why the full HMAC check after decryption is what
    /// actually matters for catching a wrong password or corrupted data; this is just a quick,
    /// cheap first check to avoid decrypting the whole entry before finding out.
    static func extractEntry(path: String, from archiveURL: URL, password: String) throws -> Data {
        let data = try Data(contentsOf: archiveURL, options: .mappedIfSafe)
        let eocdOffset = try findEOCD(in: data)
        let entries = try parseCentralDirectory(from: data, eocdOffset: eocdOffset)

        guard let entry = entries.first(where: { $0.path == path }) else {
            throw CompressionError.decompressionFailed("Entry not found: \(path)")
        }

        let dataStart = try localFileDataOffset(for: entry, in: data)
        let totalSize = Int(entry.compressedSize)
        guard dataStart + totalSize <= data.count else {
            throw ZIPBinaryError.malformedArchive("Entry data overruns archive")
        }

        let keySize = entry.aeInfo.keySize
        let saltLength = keySize.saltLength
        var cursor = dataStart

        let salt = data.subdata(in: cursor..<(cursor + saltLength))
        cursor += saltLength
        let storedVerification = data.subdata(in: cursor..<(cursor + 2))
        cursor += 2
        let cipherLength = totalSize - saltLength - 2 - 10
        guard cipherLength >= 0 else {
            throw ZIPBinaryError.malformedArchive("Entry too short for its declared AES wrapper")
        }
        let ciphertext = data.subdata(in: cursor..<(cursor + cipherLength))
        cursor += cipherLength
        let storedAuthCode = data.subdata(in: cursor..<(cursor + 10))

        let derived = try AESEncryption.deriveKeys(password: password, salt: salt, keySize: keySize)
        guard derived.passwordVerification == storedVerification else {
            throw CompressionError.incorrectPassword
        }

        let computedAuthCode = AESEncryption.authenticationCode(ciphertext: ciphertext, authenticationKey: derived.authenticationKey)
        guard computedAuthCode == storedAuthCode else {
            // A wrong password almost always fails the 2-byte check above first, but CTR
            // decryption with a wrong key never fails on its own (it just produces different
            // garbage) — the HMAC is what actually stands between a mismatched password/corrupted
            // archive and silently returning corrupted data, so this must be checked before
            // trusting anything decrypted below.
            throw CompressionError.corruptedEncryptedArchive("Authentication code mismatch for \(path)")
        }

        let compressedPayload = try AESEncryption.transformCTR(data: ciphertext, key: derived.encryptionKey)

        switch entry.aeInfo.actualCompressionMethod {
        case ZIPCompressionMethod.stored:
            return compressedPayload
        case ZIPCompressionMethod.deflate:
            return try Deflate.decompress(data: compressedPayload)
        default:
            throw CompressionError.decompressionFailed("Unsupported inner compression method \(entry.aeInfo.actualCompressionMethod)")
        }
    }

    // MARK: - Binary parsing

    private static func findEOCD(in data: Data) throws -> Int {
        try ZIPBinaryUtilities.findEOCD(in: data)
    }

    private static func parseCentralDirectory(from data: Data, eocdOffset: Int) throws -> [CentralEntry] {
        let entryCount = try data.readLE(at: eocdOffset + 10, as: UInt16.self)
        let centralDirOffset = try data.readLE(at: eocdOffset + 16, as: UInt32.self)

        var entries: [CentralEntry] = []
        var offset = Int(centralDirOffset)

        for _ in 0..<entryCount {
            let signature = try data.readLE(at: offset, as: UInt32.self)
            guard signature == ZIPSignature.centralDirectoryHeader else {
                throw ZIPBinaryError.malformedArchive("Bad central directory header signature at offset \(offset)")
            }

            let generalPurposeFlag = try data.readLE(at: offset + 8, as: UInt16.self)
            let dosTime = try data.readLE(at: offset + 12, as: UInt16.self)
            let dosDate = try data.readLE(at: offset + 14, as: UInt16.self)
            let compressedSize = try data.readLE(at: offset + 20, as: UInt32.self)
            let uncompressedSize = try data.readLE(at: offset + 24, as: UInt32.self)
            let nameLength = Int(try data.readLE(at: offset + 28, as: UInt16.self))
            let extraLength = Int(try data.readLE(at: offset + 30, as: UInt16.self))
            let commentLength = Int(try data.readLE(at: offset + 32, as: UInt16.self))
            let localHeaderOffset = try data.readLE(at: offset + 42, as: UInt32.self)

            let nameStart = offset + 46
            guard nameStart + nameLength + extraLength + commentLength <= data.count else {
                throw ZIPBinaryError.malformedArchive("Central directory entry overruns archive")
            }

            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            let entryNextOffset = nameStart + nameLength + extraLength + commentLength

            guard generalPurposeFlag & zipGeneralPurposeEncryptedFlag != 0, let path = String(data: nameData, encoding: .utf8) else {
                offset = entryNextOffset
                continue
            }

            let extraData = data.subdata(in: (nameStart + nameLength)..<(nameStart + nameLength + extraLength))
            guard let aeInfo = try AEExtraField.parse(from: extraData) else {
                // Encrypted but not via AE-x (e.g. legacy ZipCrypto) — not supported by this reader.
                offset = entryNextOffset
                continue
            }

            entries.append(CentralEntry(
                path: path,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset,
                modDate: DOSDateTime.decode(time: dosTime, date: dosDate),
                aeInfo: aeInfo
            ))

            offset = entryNextOffset
        }

        return entries
    }

    private static func localFileDataOffset(for entry: CentralEntry, in data: Data) throws -> Int {
        let localOffset = Int(entry.localHeaderOffset)
        let signature = try data.readLE(at: localOffset, as: UInt32.self)
        guard signature == ZIPSignature.localFileHeader else {
            throw ZIPBinaryError.malformedArchive("Bad local file header signature at offset \(localOffset)")
        }
        let nameLength = Int(try data.readLE(at: localOffset + 26, as: UInt16.self))
        let extraLength = Int(try data.readLE(at: localOffset + 28, as: UInt16.self))
        return localOffset + 30 + nameLength + extraLength
    }
}
