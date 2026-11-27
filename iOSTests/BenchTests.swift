import XCTest

/// Benchmark B1 of plans/ios-parity.md: flick a 10,000-row list, drawn by
/// Luau and by SwiftUI, and measure how smoothly it scrolls. `just ios-bench`
/// runs it; on a ProMotion device it measures 120 Hz.
@MainActor
final class BenchTests: XCTestCase {
    private func flick(_ mode: String) {
        let app = XCUIApplication()
        app.launchEnvironment["MOONSWIFT_BENCH"] = mode
        app.launch()
        let list = app.collectionViews["bench.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Session 1"].waitForExistence(timeout: 10))

        let options = XCTMeasureOptions()
        options.invocationOptions = [.manuallyStop]
        options.iterationCount = 5
        let metrics: [any XCTMetric] = [
            XCTOSSignpostMetric.scrollDecelerationMetric,
            XCTCPUMetric(application: app),
            XCTMemoryMetric(application: app),
        ]
        measure(metrics: metrics, options: options) {
            list.swipeUp(velocity: .fast)
            stopMeasuring()
            list.swipeDown(velocity: .fast)
        }
    }

    func testScrollLuau() { flick("luau") }

    func testScrollSwiftUI() { flick("swiftui") }
}
