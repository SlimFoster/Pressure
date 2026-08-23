import Foundation

enum ZIPBinaryError: Error {
    case malformedArchive(String)
}

// MARK: - Little-endian read/write helpers

extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { self.append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(at offset: Int, as type: T.Type) throws -> T {
        let size = MemoryLayout<T>.size
        guard offset >= 0, offset + size <= count else {
            throw ZIPBinaryError.malformedArchive("Unexpected end of data reading \(size) byte(s) at offset \(offset)")
        }
        var value: T = 0
        Swift.withUnsafeMutableBytes(of: &value) { dest in
            _ = self.copyBytes(to: dest, from: offset..<(offset + size))
        }
        return T(littleEndian: value)
    }
}

// MARK: - ZIP signatures (APPNOTE.TXT)

enum ZIPSignature {
    static let localFileHeader: UInt32 = 0x04034b50
    static let centralDirectoryHeader: UInt32 = 0x02014b50
    static let endOfCentralDirectory: UInt32 = 0x06054b50
}

enum ZIPCompressionMethod {
    static let stored: UInt16 = 0
    static let deflate: UInt16 = 8
    /// Marks an entry as AE-x encrypted; the real method is in the 0x9901 extra field.
    static let aesEncrypted: UInt16 = 99
}

/// General purpose bit flag bit 0 — set when the entry is encrypted.
let zipGeneralPurposeEncryptedFlag: UInt16 = 0x0001

// MARK: - DOS date/time (used by local/central headers)

enum DOSDateTime {
    static func encode(_ date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let year = UInt16(max(0, (c.year ?? 1980) - 1980))
        let month = UInt16(c.month ?? 1)
        let day = UInt16(c.day ?? 1)
        let hour = UInt16(c.hour ?? 0)
        let minute = UInt16(c.minute ?? 0)
        let second = UInt16(c.second ?? 0)

        let dosTime = (hour << 11) | (minute << 5) | (second / 2)
        let dosDate = (year << 9) | (month << 5) | day
        return (dosTime, dosDate)
    }

    static func decode(time: UInt16, date: UInt16) -> Date {
        var components = DateComponents()
        components.year = Int((date >> 9) & 0x7F) + 1980
        components.month = Int((date >> 5) & 0x0F)
        components.day = Int(date & 0x1F)
        components.hour = Int((time >> 11) & 0x1F)
        components.minute = Int((time >> 5) & 0x3F)
        components.second = Int((time & 0x1F) * 2)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }
}

enum ZIPBinaryUtilities {
    /// Locates the End Of Central Directory record by scanning backward from the end of the
    /// file — standard approach, since an optional comment field (up to 65535 bytes) can follow
    /// it, so it isn't always simply the last 22 bytes.
    static func findEOCD(in data: Data) throws -> Int {
        let minSize = 22
        guard data.count >= minSize else {
            throw ZIPBinaryError.malformedArchive("File too small to be a ZIP archive")
        }

        let searchWindow = min(data.count, 65557) // 22 fixed + max 65535-byte comment
        let searchStart = data.count - searchWindow

        var offset = data.count - minSize
        while offset >= searchStart {
            let signature = try data.readLE(at: offset, as: UInt32.self)
            if signature == ZIPSignature.endOfCentralDirectory {
                return offset
            }
            offset -= 1
        }
        throw ZIPBinaryError.malformedArchive("Could not locate end-of-central-directory record")
    }
}

// MARK: - AE-x extra field (header ID 0x9901)

struct AEExtraField {
    static let headerID: UInt16 = 0x9901
    /// AE-2 only — this app never writes AE-1 (AE-1 stores a plaintext CRC of the original
    /// data, which is a needless integrity/side-channel tradeoff now that the AE-2 HMAC already
    /// authenticates the ciphertext; AE-2 is what modern tools write by default).
    static let vendorVersion: UInt16 = 2
    static let vendorID = "AE"

    let keySize: AESKeySize
    let actualCompressionMethod: UInt16

    func encoded() -> Data {
        var data = Data()
        data.appendLE(AEExtraField.headerID)
        data.appendLE(UInt16(7)) // data size, fixed per spec
        data.appendLE(AEExtraField.vendorVersion)
        data.append(contentsOf: Array(AEExtraField.vendorID.utf8)) // "AE", 2 bytes
        data.append(keySize.strengthByte)
        data.appendLE(actualCompressionMethod)
        return data
    }

    /// Scans a local/central header's extra field block for a 0x9901 sub-field.
    static func parse(from extraField: Data) throws -> AEExtraField? {
        var offset = 0
        while offset + 4 <= extraField.count {
            let id = try extraField.readLE(at: offset, as: UInt16.self)
            let size = try extraField.readLE(at: offset + 2, as: UInt16.self)
            let subFieldStart = offset + 4
            guard subFieldStart + Int(size) <= extraField.count else {
                throw ZIPBinaryError.malformedArchive("Extra field sub-block overruns its container")
            }

            if id == headerID {
                guard size >= 7 else {
                    throw ZIPBinaryError.malformedArchive("AE-x extra field too short")
                }
                let strength = extraField[subFieldStart + 4]
                guard let keySize = AESKeySize(strengthByte: strength) else {
                    throw ZIPBinaryError.malformedArchive("Unknown AES strength byte \(strength)")
                }
                let actualMethod = try extraField.readLE(at: subFieldStart + 5, as: UInt16.self)
                return AEExtraField(keySize: keySize, actualCompressionMethod: actualMethod)
            }

            offset = subFieldStart + Int(size)
        }
        return nil
    }
}
