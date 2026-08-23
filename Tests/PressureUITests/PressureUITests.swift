import XCTest

/// Smoke tests for the current Simple/Power mode UI. This intentionally stays small — it
/// replaces a much larger suite that had drifted to test an entirely defunct single-form UI
/// ("Select Files"/"Compress"/"Decompress" buttons) that predates even the old two-pane
/// redesign. Deeper coverage of Power mode's editing flows (add/delete/rename, sidebar
/// navigation, encryption/split) is real, separate work — not attempted here.
final class PressureUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5.0))
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// SwiftUI `Text` content in this AppKit-hosted accessibility bridge surfaces as the
    /// element's *value*, not its label (unlike `Button`, whose label is populated normally) —
    /// so static text needs to be matched against either.
    private func staticText(_ text: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@", text, text)).firstMatch
    }

    // MARK: - App launch

    func testAppLaunches() {
        XCTAssertGreaterThan(app.windows.count, 0, "App should have at least one window")
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testWindowHasReasonableSize() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertGreaterThanOrEqual(window.frame.width, 500)
        XCTAssertGreaterThanOrEqual(window.frame.height, 400)
    }

    // MARK: - Mode toggle

    func testModeToggleExists() {
        XCTAssertTrue(app.radioButtons["Simple"].waitForExistence(timeout: 5.0), "Simple mode toggle should exist")
        XCTAssertTrue(app.radioButtons["Power"].exists, "Power mode toggle should exist")
    }

    func testSwitchingToSimpleModeShowsDropZone() {
        app.radioButtons["Simple"].tap()
        XCTAssertTrue(staticText("Drop files here").waitForExistence(timeout: 5.0), "Simple mode should show its drop zone")
        // `.buttonStyle(.link)` renders as an accessibility link, not a button.
        XCTAssertTrue(app.links["or choose files..."].exists, "Simple mode should offer a file picker link")
    }

    func testSwitchingToPowerModeShowsToolbar() {
        app.radioButtons["Power"].tap()
        XCTAssertTrue(app.buttons["Add Files"].waitForExistence(timeout: 5.0), "Power mode toolbar should have Add Files")
        XCTAssertTrue(app.buttons["Extract All"].exists, "Power mode toolbar should have Extract All")
        XCTAssertTrue(app.buttons["Delete"].exists, "Power mode toolbar should have Delete")
        XCTAssertTrue(app.buttons["Rename"].exists, "Power mode toolbar should have Rename")
    }

    func testPowerMode_EmptyState_OffersOpenAndNewArchive() {
        app.radioButtons["Power"].tap()
        // If an archive from a previous run is still "open" in this session's persisted state,
        // the empty-state affordances won't be present — this test only asserts them when there
        // genuinely is no archive open yet, rather than forcing a specific starting state.
        if staticText("No archive open").waitForExistence(timeout: 3.0) {
            XCTAssertTrue(app.buttons["Open Archive…"].exists)
            XCTAssertTrue(app.buttons["New Archive…"].exists)
        }
    }
}
