import XCTest

/// `examples/sheprd` driven with real taps: Home's rows, menus and swipes,
/// and Settings' pages, pickers and edit mode. Leaves screenshots.
@MainActor
final class ExampleTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["MOONSWIFT_EXAMPLE"] = "sheprd"
        app.launchEnvironment["MOONSWIFT_PLAIN"] = "1"
        app.launch()
        XCTAssertTrue(app.staticTexts["Weather widget"].waitForExistence(timeout: 20))
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTheEdgeIndexScrollsToASection() {
        let first = app.staticTexts["Weather widget"].firstMatch
        let top = first.frame.minY
        // The strip is hidden from VoiceOver, as the system's index is:
        // touch its letters where they are drawn, Idle's last, then
        // Favorites' first. The demo is short, so the list moves a little.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.972, dy: 0.587)).tap()
        let down = NSPredicate { _, _ in first.frame.minY < top - 20 }
        wait(for: [expectation(for: down, evaluatedWith: nil)], timeout: 5)
        shot("edge-index-idle")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.972, dy: 0.509)).tap()
        let back = NSPredicate { _, _ in first.frame.minY > top - 20 }
        wait(for: [expectation(for: back, evaluatedWith: nil)], timeout: 5)
    }

    func testHomeFoldsSwipesAndOpensAChat() {
        shot("home")
        // A section folds from its header.
        app.buttons["Working, 1"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Show the chart legend"].waitForNonExistence(timeout: 5))
        app.buttons["Working, 1"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Show the chart legend"].waitForExistence(timeout: 5))

        // Swiping a row offers its actions; Close asks first.
        app.staticTexts["Landing page copy"].swipeLeft()
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Close Chat"].firstMatch.waitForExistence(timeout: 5))
        shot("close-dialog")
        app.buttons["Close Chat"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Landing page copy"].waitForNonExistence(timeout: 5))

        // Answering the question turns its card back into a row.
        app.buttons["Allow once"].tap()
        XCTAssertTrue(app.buttons["Allow once"].waitForNonExistence(timeout: 5))

        // A row pushes its chat, a markdown document under its prompt.
        app.staticTexts["Weather widget"].tap()
        XCTAssertTrue(app.staticTexts["Checked"].waitForExistence(timeout: 5))
        shot("chat")
        let composer = app.descendants(matching: .any).matching(identifier: "composer").firstMatch
        composer.tap()
        composer.typeText("Ship it")
        shot("chat-typing")
    }

    func testWorkspacesFoldAndOfferActions() {
        app.tabBars.buttons["Workspaces"].tap()
        XCTAssertTrue(app.staticTexts["chart legend"].waitForExistence(timeout: 5))
        shot("workspaces")

        // A computer's header folds its repositories away.
        app.staticTexts["Studio"].tap()
        XCTAssertTrue(app.staticTexts["chart legend"].waitForNonExistence(timeout: 5))
        app.staticTexts["Studio"].tap()
        XCTAssertTrue(app.staticTexts["chart legend"].waitForExistence(timeout: 5))

        // Its menu holds a toggle and asks before forgetting.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'More' OR label CONTAINS 'ellipsis'")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Forget…"].waitForExistence(timeout: 5))
        shot("workspaces-menu")
        app.buttons["Forget…"].tap()
        XCTAssertTrue(app.buttons["Forget"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["Forget"].firstMatch.tap()

        // A workspace opens its shell, a view the app draws natively.
        app.staticTexts["chart legend"].tap()
        XCTAssertTrue(app.staticTexts["~/forecast main ❯ swift test"].waitForExistence(timeout: 5))
        shot("terminal")
    }

    func testPullRequestsLeadToSettings() {
        app.tabBars.buttons["PRs"].tap()
        XCTAssertTrue(app.staticTexts["No GitHub account"].waitForExistence(timeout: 5))
        shot("prs")
        app.buttons["Open Settings › GitHub"].tap()
        XCTAssertTrue(app.navigationBars["GitHub"].waitForExistence(timeout: 5))
    }

    func testSettingsPagesAndAppearance() {
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Computers"].waitForExistence(timeout: 5))
        shot("settings")

        app.staticTexts["Chats"].tap()
        let returnSends = app.switches["Return Sends"]
        XCTAssertTrue(returnSends.waitForExistence(timeout: 5))
        returnSends.switches.firstMatch.tap()
        XCTAssertEqual(returnSends.value as? String, "1")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        app.staticTexts["Terminal Keys"].tap()
        XCTAssertTrue(app.staticTexts["esc"].waitForExistence(timeout: 5))
        app.staticTexts["esc"].swipeLeft()
        app.buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["esc"].waitForNonExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let appearance = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Appearance'")).firstMatch
        appearance.tap()
        app.buttons["Dark"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Appearance, Dark"].waitForExistence(timeout: 5))
        sleep(1)
        shot("settings-dark")
        appearance.tap()
        app.buttons["System"].firstMatch.tap()
    }
}
