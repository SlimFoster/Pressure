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
            return UTType(filenameExtension: "bz2") ?? .data
        case .z:
            return UTType(filenameExtension: "Z") ?? .data
        case .rar:
            return UTType(filenameExtension: "rar") ?? .data
        }
    }
}
