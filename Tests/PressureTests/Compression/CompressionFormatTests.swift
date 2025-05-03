import XCTest
import UniformTypeIdentifiers
@testable import Pressure

final class CompressionFormatTests: XCTestCase {
    
    func testCompressionFormat_FileTypes() {
        XCTAssertEqual(CompressionFormat.zip.fileType, .zip)
        XCTAssertEqual(CompressionFormat.gzip.fileType, .gzip)
        // TAR and BZIP2 use filenameExtension, so we test differently
        let tarType = CompressionFormat.tar.fileType
        XCTAssertNotNil(tarType)
        
        let bzip2Type = CompressionFormat.bzip2.fileType
        XCTAssertNotNil(bzip2Type)
        
        let zType = CompressionFormat.z.fileType
        XCTAssertNotNil(zType)
        
        let rarType = CompressionFormat.rar.fileType
        XCTAssertNotNil(rarType)
    }
    
    func testCompressionFormat_AllCases() {
        let allFormats = CompressionFormat.allCases
        XCTAssertEqual(allFormats.count, 6)
        XCTAssertTrue(allFormats.contains(.zip))
        XCTAssertTrue(allFormats.contains(.gzip))
        XCTAssertTrue(allFormats.contains(.tar))
        XCTAssertTrue(allFormats.contains(.bzip2))
        XCTAssertTrue(allFormats.contains(.z))
        XCTAssertTrue(allFormats.contains(.rar))
    }
    
    func testCompressionFormat_RawValues() {
        XCTAssertEqual(CompressionFormat.zip.rawValue, "zip")
        XCTAssertEqual(CompressionFormat.gzip.rawValue, "gzip")
        XCTAssertEqual(CompressionFormat.tar.rawValue, "tar")
        XCTAssertEqual(CompressionFormat.bzip2.rawValue, "bzip2")
        XCTAssertEqual(CompressionFormat.z.rawValue, "z")
        XCTAssertEqual(CompressionFormat.rar.rawValue, "rar")
    }
    
    func testCompressionFormat_InitFromRawValue() {
        XCTAssertEqual(CompressionFormat(rawValue: "zip"), .zip)
        XCTAssertEqual(CompressionFormat(rawValue: "gzip"), .gzip)
        XCTAssertEqual(CompressionFormat(rawValue: "tar"), .tar)
        XCTAssertEqual(CompressionFormat(rawValue: "bzip2"), .bzip2)
        XCTAssertEqual(CompressionFormat(rawValue: "z"), .z)
        XCTAssertEqual(CompressionFormat(rawValue: "rar"), .rar)
    }
}
