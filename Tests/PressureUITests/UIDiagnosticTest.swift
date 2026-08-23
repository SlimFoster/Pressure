import XCTest

final class UIDiagnosticTest: XCTestCase {
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        sleep(3) // Wait for UI to fully load
    }
    
    func testDumpFullUIHierarchy() {
        print("\n" + String(repeating: "=", count: 80))
        print("FULL UI HIERARCHY DUMP")
        print(String(repeating: "=", count: 80) + "\n")
        
        // Get the main window
        guard app.windows.count > 0 else {
            print("ERROR: No windows found!")
            XCTFail("No windows found")
            return
        }
        
        let window = app.windows.firstMatch
        print("Window: \(window.title)")
        print("Window exists: \(window.exists)")
        print("Window frame: \(window.frame)")
        print("\n")
        
        // Dump entire accessibility hierarchy
        print("=== FULL ACCESSIBILITY HIERARCHY ===")
        let snapshot = try? window.snapshot()
        if let snapshot = snapshot {
            dumpElement(snapshot, indent: 0)
        } else {
            print("Could not get snapshot")
        }
        
        print("\n" + String(repeating: "=", count: 80))
        print("END OF DUMP")
        print(String(repeating: "=", count: 80) + "\n")
        
        // Always pass - this is just for diagnostics
        XCTAssertTrue(true)
    }
    
    private func dumpElement(_ element: XCUIElementSnapshot, indent: Int) {
        let indentStr = String(repeating: "  ", count: indent)
        let elementType = element.elementType.rawValue
        let label = element.label.isEmpty ? "(no label)" : element.label
        let identifier = element.identifier.isEmpty ? "(no id)" : element.identifier
        let value = element.value as? String ?? ""
        let isEnabled = element.isEnabled ? "enabled" : "disabled"
        let isVisible = element.frame != .zero ? "visible" : "hidden"
        
        print("\(indentStr)[\(elementType)] label:'\(label)' id:'\(identifier)' value:'\(value)' \(isEnabled) \(isVisible)")
        
        if element.frame != .zero {
            print("\(indentStr)  frame: \(element.frame)")
        }
        
        for child in element.children {
            dumpElement(child, indent: indent + 1)
        }
    }
}
