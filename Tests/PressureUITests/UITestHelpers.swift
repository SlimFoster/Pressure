import XCTest

class UITestHelpers {
    static func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        return element.waitForExistence(timeout: timeout)
    }
    
    static func waitForElementToDisappear(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
    
    static func waitForText(_ app: XCUIApplication, text: String, timeout: TimeInterval = 5.0) -> Bool {
        let element = app.staticTexts[text]
        return element.waitForExistence(timeout: timeout)
    }
    
    static func verifyButtonState(_ button: XCUIElement, expectedEnabled: Bool, file: StaticString = #file, line: UInt = #line) {
        if expectedEnabled {
            XCTAssertTrue(button.isEnabled || button.isHittable, "Button should be enabled", file: file, line: line)
        } else {
            XCTAssertFalse(button.isEnabled && button.isHittable, "Button should be disabled", file: file, line: line)
        }
    }
    
    static func createTestFile(in directory: URL, name: String, content: String) throws -> URL {
        let fileURL = directory.appendingPathComponent(name)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }
}
