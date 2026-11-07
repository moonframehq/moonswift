import XCTest

/// The beta app on a simulator, with real taps.
@MainActor
final class BetaTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MOONSWIFT_RESET"] = "1"
        app.launch()
        XCTAssertTrue(app.buttons["more"].waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTapsReachLuau() {
        app.buttons["more"].tap()
        app.buttons["more"].tap()
        XCTAssertTrue(app.staticTexts["2"].waitForExistence(timeout: 5))
        shot("counter")
        app.buttons["nav-tasks"].tap()
        XCTAssertTrue(app.staticTexts["Change it in the inspector"].waitForExistence(timeout: 5))
        shot("tasks")
    }

    func testTheSparklePicksByTouchAndEditsLive() {
        let more = app.buttons["more"]
        app.buttons["moon.sparkle"].tap()
        more.tap()

        let element = app.staticTexts["moon.element"]
        XCTAssertTrue(element.waitForExistence(timeout: 5), "the inspector should open on the pick")
        XCTAssertEqual(element.label, #"button "More""#)
        shot("inspected")

        let editor = app.textViews["moon.source"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.tap()
        editor.typeKey("a", modifierFlags: .command)
        editor.typeText(#"return mod { view = function() return ui.text { "typed on a phone" } end }"#)
        XCTAssertTrue(app.staticTexts["typed on a phone"].waitForExistence(timeout: 5), "typing should redraw the app")
        shot("edited")
    }
}
