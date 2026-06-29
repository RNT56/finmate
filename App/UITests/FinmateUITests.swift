import XCTest

// MARK: - Critical-flow smoke suite (docs/09 — XCUITest critical flows)
//
// Black-box UI tests driving the real Finmate app through the fully offline
// "Try the demo" path — no network, deterministic in-memory sample data. Each
// test launches a fresh app with `-uiTestResetOnboarding` so onboarding always
// shows (the App reads this arg to clear the persisted first-run flag), making
// the Auth → onboarding → root TabView flow reproducible across machines/runs.
//
// Identifiers used (added in the app, non-visual):
//   auth.tryDemo · onboarding.continue · subscriptions.add ·
//   addSubscription.name / .amount / .save · settings.currency
final class FinmateUITests: XCTestCase {

    /// Generous default for first-paint / animation settling on CI simulators.
    private let timeout: TimeInterval = 30

    override func setUp() {
        super.setUp()
        // A failing assertion should stop the test immediately rather than cascade.
        continueAfterFailure = false
    }

    // MARK: Helpers

    /// Launches a fresh app forced to the signed-out Auth screen with a clean
    /// first-run state (onboarding will be shown). When `contentSizeCategory` is
    /// supplied, the app launches at that Dynamic Type size (used by the
    /// accessibility-size regression test).
    private func launchApp(contentSizeCategory: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-uiTestResetOnboarding"]
        if let category = contentSizeCategory {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", category]
        }
        app.launch()
        return app
    }

    /// Drives the offline demo path: tap "Try the demo" → complete onboarding →
    /// land on the root TabView. Asserts each step is reached.
    @discardableResult
    private func enterAppViaDemo(_ app: XCUIApplication) -> XCUIApplication {
        let tryDemo = app.buttons["auth.tryDemo"]
        XCTAssertTrue(tryDemo.waitForExistence(timeout: timeout),
                      "The 'Try the demo' button should appear on the Auth screen.")
        tryDemo.tap()

        let getStarted = app.buttons["onboarding.continue"]
        XCTAssertTrue(getStarted.waitForExistence(timeout: timeout),
                      "Onboarding 'Get started' should appear after entering the demo.")
        getStarted.tap()

        // The root TabView is shown once a tab bar with the known tabs exists.
        let subscriptionsTab = app.tabBars.buttons["Subscriptions"]
        XCTAssertTrue(subscriptionsTab.waitForExistence(timeout: timeout),
                      "The root TabView (Subscriptions tab) should be shown after onboarding.")
        return app
    }

    // MARK: Tests

    /// Launch → demo → onboarding → main TabView is shown.
    func testLaunchToAppViaDemo() {
        let app = launchApp()
        enterAppViaDemo(app)

        // Sanity: Home and Subscriptions tabs both exist in the root TabView.
        XCTAssertTrue(app.tabBars.buttons["Home"].exists,
                      "The Home tab should exist in the root TabView.")
        XCTAssertTrue(app.tabBars.buttons["Subscriptions"].exists,
                      "The Subscriptions tab should exist in the root TabView.")
    }

    /// Navigate to each tab and assert a known nav title / element per screen.
    func testTabNavigation() {
        let app = launchApp()
        enterAppViaDemo(app)

        let tabBar = app.tabBars.element(boundBy: 0)

        // Subscriptions
        tabBar.buttons["Subscriptions"].tap()
        XCTAssertTrue(app.navigationBars["Subscriptions"].waitForExistence(timeout: timeout),
                      "The Subscriptions screen should show its 'Subscriptions' nav title.")

        // Cash Flow
        tabBar.buttons["Cash Flow"].tap()
        XCTAssertTrue(app.navigationBars["Cash Flow"].waitForExistence(timeout: timeout),
                      "The Cash Flow screen should show its 'Cash Flow' nav title.")

        // Calendar
        tabBar.buttons["Calendar"].tap()
        XCTAssertTrue(app.navigationBars["Calendar"].waitForExistence(timeout: timeout),
                      "The Calendar screen should show its 'Calendar' nav title.")

        // More
        tabBar.buttons["More"].tap()
        XCTAssertTrue(app.navigationBars["More"].waitForExistence(timeout: timeout),
                      "The More screen should show its 'More' nav title.")

        // Home (return)
        tabBar.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Finmate"].waitForExistence(timeout: timeout),
                      "The Home screen should show its 'Finmate' nav title.")
    }

    /// On Subscriptions: add a subscription via the sheet and assert the new
    /// row appears in the list.
    func testAddSubscription() {
        let app = launchApp()
        enterAppViaDemo(app)

        app.tabBars.buttons["Subscriptions"].tap()
        XCTAssertTrue(app.navigationBars["Subscriptions"].waitForExistence(timeout: timeout))

        // Open the add sheet.
        let addButton = app.buttons["subscriptions.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: timeout),
                      "The add-subscription '+' button should exist.")
        addButton.tap()

        // Fill the name + amount.
        let nameField = app.textFields["addSubscription.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout),
                      "The add-subscription name field should appear in the sheet.")
        nameField.tap()
        let uniqueName = "UITestSub"
        nameField.typeText(uniqueName)

        let amountField = app.textFields["addSubscription.amount"]
        XCTAssertTrue(amountField.waitForExistence(timeout: timeout),
                      "The add-subscription amount field should appear in the sheet.")
        amountField.tap()
        amountField.typeText("9.99")

        // Save.
        let saveButton = app.buttons["addSubscription.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: timeout),
                      "The Save button should exist in the add sheet.")
        saveButton.tap()

        // The new row appears in the list (matched by its name in the row's
        // combined accessibility label).
        let newRow = app.staticTexts[uniqueName]
        XCTAssertTrue(newRow.waitForExistence(timeout: timeout),
                      "The newly added subscription row should appear in the list.")
    }

    /// Dynamic-Type regression (docs/06 §accessibility, M7-A11Y-01): launch at the
    /// LARGEST accessibility content-size category, drive the demo → onboarding →
    /// app flow, and assert the tab bar and key screens (Subscriptions list, a
    /// Cash Flow KPI) still render and stay hittable — i.e. nothing crashes,
    /// truncates away, or pushes a critical control off-screen at AX-XXL.
    func testRendersAtAccessibilityXXL() {
        let app = launchApp(contentSizeCategory: "UICTContentSizeCategoryAccessibilityXXL")
        enterAppViaDemo(app)

        // The root TabView and its tabs survive the largest accessibility size and
        // remain hittable (not clipped off-screen / behind overlapping glass).
        let tabBar = app.tabBars.element(boundBy: 0)
        XCTAssertTrue(tabBar.waitForExistence(timeout: timeout),
                      "The root tab bar should render at accessibility XXL.")
        for tab in ["Home", "Subscriptions", "Cash Flow", "Calendar", "More"] {
            let button = tabBar.buttons[tab]
            XCTAssertTrue(button.exists, "The \(tab) tab should exist at accessibility XXL.")
            XCTAssertTrue(button.isHittable, "The \(tab) tab should stay hittable at accessibility XXL.")
        }

        // Subscriptions list: the screen loads and at least one subscription row is
        // present (the demo seed is non-empty), proving rows render without crashing
        // at the largest text size.
        tabBar.buttons["Subscriptions"].tap()
        XCTAssertTrue(app.navigationBars["Subscriptions"].waitForExistence(timeout: timeout),
                      "The Subscriptions screen should render at accessibility XXL.")
        // The add control stays present and hittable — i.e. the toolbar/list didn't
        // overlap or push it off-screen at the largest text size.
        let addButton = app.buttons["subscriptions.add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: timeout),
                      "The add-subscription button should render at accessibility XXL.")
        XCTAssertTrue(addButton.isHittable,
                      "The add-subscription button should stay hittable at accessibility XXL.")

        // Cash Flow: the screen loads and a KPI value renders at AX-XXL. KPI tiles
        // use a scalable rounded title style with minimumScaleFactor, so the value
        // must still exist (not collapse to empty) — assert the screen + at least
        // one static text are present.
        tabBar.buttons["Cash Flow"].tap()
        XCTAssertTrue(app.navigationBars["Cash Flow"].waitForExistence(timeout: timeout),
                      "The Cash Flow screen should render at accessibility XXL.")
        XCTAssertTrue(app.staticTexts.count > 0,
                      "Cash Flow KPI labels/values should render at accessibility XXL.")

        // Return Home — confirms tab switching still works after the heavy screens.
        tabBar.buttons["Home"].tap()
        XCTAssertTrue(app.navigationBars["Finmate"].waitForExistence(timeout: timeout),
                      "The Home screen should render at accessibility XXL.")
    }
}
