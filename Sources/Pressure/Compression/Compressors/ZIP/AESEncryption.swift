import Foundation
import CommonCrypto

/// CommonCrypto-based primitives for WinZip AE-2 AES encryption (see APPNOTE.TXT extra field
/// 0x9901 and the WinZip AES Encryption Specification). No new dependency is needed —
/// CommonCrypto ships with the SDK and exposes PBKDF2-HMAC-SHA1 and AES-ECB directly.
enum AESKeySize: CaseIterable {
    case aes128
    case aes192
    case aes256

    var keyLength: Int {
        switch self {
        case .aes128: return 16
        case .aes192: return 24
        case .aes256: return 32
        }
    }

    /// Salt length per the WinZip spec — not the same as the key length.
    var saltLength: Int {
        switch self {
        case .aes128: return 8
        case .aes192: return 12
        case .aes256: return 16
        }
    }

    /// The "AES strength" byte stored in the 0x9901 extra field.
    var strengthByte: UInt8 {
        switch self {
        case .aes128: return 1
        case .aes192: return 2
        case .aes256: return 3
        }
    }

    init?(strengthByte: UInt8) {
        switch strengthByte {
        case 1: self = .aes128
        case 2: self = .aes192
        case 3: self = .aes256
        default: return nil
        }
    }
}

struct AESDerivedKeys {
    let encryptionKey: Data
    let authenticationKey: Data
    let passwordVerification: Data
}

enum AESEncryption {
    /// PBKDF2-HMAC-SHA1, 1000 iterations (fixed by the WinZip spec), deriving
    /// encryptionKey || authenticationKey || 2-byte password-verification value, each
    /// `keySize.keyLength` bytes except the verification value.
    static func deriveKeys(password: String, salt: Data, keySize: AESKeySize) throws -> AESDerivedKeys {
        let keyLength = keySize.keyLength
        let derivedLength = 2 * keyLength + 2
        var derived = [UInt8](repeating: 0, count: derivedLength)
        let passwordBytes = Array(password.utf8)
        let saltBytes = [UInt8](salt)

        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passwordBytes, passwordBytes.count,
            saltBytes, saltBytes.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
            1000,
            &derived, derivedLength
        )
        guard status == kCCSuccess else {
            throw CompressionError.compressionFailed("PBKDF2 key derivation failed (status \(status))")
        }

        return AESDerivedKeys(
            encryptionKey: Data(derived[0..<keyLength]),
            authenticationKey: Data(derived[keyLength..<(2 * keyLength)]),
            passwordVerification: Data(derived[(2 * keyLength)..<derivedLength])
        )
    }

    /// AES-CTR transform (symmetric — the same operation encrypts and decrypts) using WinZip's
    /// counter convention: a 16-byte counter block starting at 1, incremented as a
    /// *little-endian* integer per 16-byte block.
    ///
    /// This deliberately does NOT use CommonCrypto's built-in `kCCModeCTR` — standard CTR-mode
    /// implementations (CommonCrypto included, matching OpenSSL) increment the counter as a
    /// *big-endian* integer, which silently produces wrong output past the first block if used
    /// directly here. Instead this generates the keystream manually: encrypt each little-endian
    /// counter block with AES-ECB (a single, unchained block operation with no such ambiguity),
    /// then XOR with the data. Verified against PyCryptodome's `Counter.new(little_endian=True)`
    /// convention, which pyzipper (a reference WinZip-AES implementation) relies on for the same
    /// reason.
    static func transformCTR(data: Data, key: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }

        var cryptorRef: CCCryptorRef?
        let keyBytes = [UInt8](key)
        let createStatus = CCCryptorCreateWithMode(
            CCOperation(kCCEncrypt),
            CCMode(kCCModeECB),
            CCAlgorithm(kCCAlgorithmAES),
            CCPadding(ccNoPadding),
            nil,
            keyBytes, keyBytes.count,
            nil, 0,
            0,
            CCModeOptions(0),
            &cryptorRef
        )
        guard createStatus == kCCSuccess, let cryptor = cryptorRef else {
            throw CompressionError.compressionFailed("Failed to create AES cryptor (status \(createStatus))")
        }
        defer { CCCryptorRelease(cryptor) }

        var output = [UInt8](repeating: 0, count: data.count)
        var counter = [UInt8](repeating: 0, count: 16)
        counter[0] = 1 // WinZip AE-x counter starts at 1

        let dataBytes = [UInt8](data)
        var keystream = [UInt8](repeating: 0, count: 16)
        var offset = 0

        while offset < dataBytes.count {
            var moved = 0
            let updateStatus = CCCryptorUpdate(cryptor, counter, 16, &keystream, 16, &moved)
            guard updateStatus == kCCSuccess else {
                throw CompressionError.compressionFailed("AES keystream generation failed (status \(updateStatus))")
            }

            let blockLength = min(16, dataBytes.count - offset)
            for i in 0..<blockLength {
                output[offset + i] = dataBytes[offset + i] ^ keystream[i]
            }

            offset += blockLength
            incrementLittleEndian(&counter)
        }

        return Data(output)
    }

    private static func incrementLittleEndian(_ counter: inout [UInt8]) {
        for i in 0..<counter.count {
            counter[i] = counter[i] &+ 1
            if counter[i] != 0 { break }
        }
    }

    /// HMAC-SHA1 over the ciphertext (encrypt-then-MAC), truncated to 10 bytes per the WinZip
    /// spec's "HMAC-SHA1-80" authentication code.
    static func authenticationCode(ciphertext: Data, authenticationKey: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        let keyBytes = [UInt8](authenticationKey)
        let dataBytes = [UInt8](ciphertext)
        CCHmac(CCHmacAlgorithm(kCCHmacAlgSHA1), keyBytes, keyBytes.count, dataBytes, dataBytes.count, &digest)
        return Data(digest.prefix(10))
    }

    static func randomSalt(length: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        guard status == errSecSuccess else {
            throw CompressionError.compressionFailed("Failed to generate random salt")
        }
        return Data(bytes)
    }
}
