import Foundation

enum CompressionError: LocalizedError {
    case unsupportedFormat(String)
    case compressionFailed(String)
    case decompressionFailed(String)
    case invalidInput(String)
    
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
        }
    }
}
