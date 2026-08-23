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
    
    static func performDragAndDrop(from sourceElement: XCUIElement, to destinationElement: XCUIElement, duration: TimeInterval = 0.5) {
        let sourceCoordinate = sourceElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let destinationCoordinate = destinationElement.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        sourceCoordinate.press(forDuration: duration, thenDragTo: destinationCoordinate)
    }
    
    static func findTableInScrollView(_ app: XCUIApplication, index: Int = 0) -> XCUIElement? {
        let tables = app.tables
        guard tables.count > index else { return nil }
        return tables.element(boundBy: index)
    }
    
    static func waitForTableToLoad(_ table: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        return table.waitForExistence(timeout: timeout)
    }
}



