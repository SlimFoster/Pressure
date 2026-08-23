import Foundation

enum CompressionError: LocalizedError {
    case unsupportedFormat(String)
    case compressionFailed(String)
    case decompressionFailed(String)
    case invalidInput(String)
    case incorrectPassword
    case corruptedEncryptedArchive(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let message):
            return "Unsupported format: \(message)"
        case .compressionFailed(let message):
            return "Compression failed: \(message)"
        case .decompressionFailed(let message):
            return "Decompression failed: \(message)"
        case .invalidInput(let message):
            return "Invalid input: \(message)"
        case .incorrectPassword:
            return "Incorrect password"
        case .corruptedEncryptedArchive(let message):
            return "Encrypted archive is corrupted or was tampered with: \(message)"
        }
    }
}
