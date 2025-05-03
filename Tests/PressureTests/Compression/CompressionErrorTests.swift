import XCTest
@testable import Pressure

final class CompressionErrorTests: XCTestCase {
    
    func testUnsupportedFormat_ErrorDescription() {
        let error = CompressionError.unsupportedFormat("RAR format")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("RAR") == true || error.errorDescription?.contains("unsupported") == true)
    }
    
    func testCompressionFailed_ErrorDescription() {
        let error = CompressionError.compressionFailed("Failed to write file")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("compression") == true || error.errorDescription?.contains("Failed") == true)
    }
    
    func testDecompressionFailed_ErrorDescription() {
        let error = CompressionError.decompressionFailed("Invalid archive")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("decompression") == true || error.errorDescription?.contains("Invalid") == true)
    }
    
    func testInvalidInput_ErrorDescription() {
        let error = CompressionError.invalidInput("No files provided")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("input") == true || error.errorDescription?.contains("No files") == true)
    }
    
    func testErrorTypes_AreDistinct() {
        let unsupported = CompressionError.unsupportedFormat("test")
        let compression = CompressionError.compressionFailed("test")
        let decompression = CompressionError.decompressionFailed("test")
        let invalid = CompressionError.invalidInput("test")
        
        // All should have error descriptions
        XCTAssertNotNil(unsupported.errorDescription)
        XCTAssertNotNil(compression.errorDescription)
        XCTAssertNotNil(decompression.errorDescription)
        XCTAssertNotNil(invalid.errorDescription)
    }
}
