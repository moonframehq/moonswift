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
        let focused = expectation(for: NSPredicate(format: "hasKeyboardFocus == true"), evaluatedWith: editor)
        wait(for: [focused], timeout: 5)
        // Empty it as a person would: the cursor at the end, then hold delete.
        // With a hardware keyboard attached there are no keys: ⌘A then.
        let delete = app.keys["delete"]
        if delete.waitForExistence(timeout: 2) {
            for _ in 0..<4 { editor.swipeUp() }
            editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.97)).tap()
            // Held, delete speeds up to whole words; a long file takes a while.
            for _ in 0..<6 where !(editor.value as? String ?? "").isEmpty {
                delete.press(forDuration: 10)
            }
        } else {
            editor.typeKey("a", modifierFlags: .command)
        }
        editor.typeText(#"return mod { view = function() return ui.text { "typed on a phone" } end }"#)
        let typed = app.staticTexts["typed on a phone"].waitForExistence(timeout: 5)
        if !typed {
            let holds = XCTAttachment(string: editor.value as? String ?? "")
            holds.name = "editor"
            holds.lifetime = .keepAlways
            add(holds)
        }
        XCTAssertTrue(typed, "typing should redraw the app")
        shot("edited")
    }
}
