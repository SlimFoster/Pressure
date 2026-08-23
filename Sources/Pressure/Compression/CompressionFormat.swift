import Foundation
import UniformTypeIdentifiers

enum CompressionFormat: String, CaseIterable {
    case zip
    case gzip
    case tar
    case bzip2
    case z
    case rar
    
    var fileType: UTType {
        switch self {
        case .zip:
            return .zip
        case .gzip:
            return .gzip
        case .tar:
            return UTType(filenameExtension: "tar") ?? .data
        case .bzip2:
            return .bz2
        case .z:
            return UTType(filenameExtension: "Z") ?? .data
        case .rar:
            return UTType(filenameExtension: "rar") ?? .data
        }
    }

    var supportsCompressionLevel: Bool {
        switch self {
        case .zip:
            return true
        default:
            return false
        }
    }
}
