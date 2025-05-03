import XCTest

final class PressureUITestsLaunchTests: XCTestCase {
    
    func testLaunchPerformance() throws {
        if #available(macOS 13.0, *) {
            // This measures how long it takes to launch the app
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                let app = XCUIApplication()
                app.launch()
                
                // Wait for app to be ready before measurement completes
                let title = app.staticTexts["Pressure"]
                _ = title.waitForExistence(timeout: 5.0)
            }
        }
    }
    
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Verify app launched successfully
        XCTAssertEqual(app.state, .runningForeground, "App should be running in foreground")
        
        // Verify app UI is ready
        let title = app.staticTexts["Pressure"]
        XCTAssertTrue(title.waitForExistence(timeout: 5.0), "App UI should be ready after launch")
    }
    
    func testLaunchTime() throws {
        // Measure launch time without using measure() for more control
        let startTime = Date()
        let app = XCUIApplication()
        app.launch()
        
        // Wait for UI to be ready
        let title = app.staticTexts["Pressure"]
        XCTAssertTrue(title.waitForExistence(timeout: 5.0), "App should launch within 5 seconds")
        
        let launchTime = Date().timeIntervalSince(startTime)
        XCTAssertLessThan(launchTime, 5.0, "App should launch quickly")
        
        // Verify app is functional
        XCTAssertEqual(app.state, .runningForeground, "App should be in foreground")
    }
}
