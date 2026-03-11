import XCTest

final class LockOutUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
    }

    func testOnboardingPresetSelectionFlow() throws {
        launch(arguments: ["--uitesting", "--reset-onboarding"])

        XCTAssertTrue(app.staticTexts["Choose a working style"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Developer Focus"].exists)
        XCTAssertTrue(app.buttons["Strict Recovery"].exists)
        XCTAssertTrue(app.buttons["Writer Gentle Routine"].exists)

        app.buttons["Writer Gentle Routine"].click()
        app.buttons["onboarding.continue"].click()

        XCTAssertTrue(app.staticTexts["Enable essential permissions"].waitForExistence(timeout: 5))
    }

    func testSettingsScreenShowsSyncAndTransferSections() throws {
        launch()
        openSidebarItem(accessibilityID: "sidebar.settings", fallbackLabel: "Settings")

        XCTAssertTrue(app.staticTexts["Sync Status"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Export Settings"].exists)
        XCTAssertTrue(app.buttons["Import Settings"].exists)
    }

    func testProfileEditorShowsFullRoutineControls() throws {
        launch()
        openSidebarItem(accessibilityID: "sidebar.profiles", fallbackLabel: "Profiles")

        let saveCurrent = app.buttons["profiles.saveCurrent"]
        if saveCurrent.waitForExistence(timeout: 5) {
            saveCurrent.click()
        } else {
            let fallbackSaveCurrent = app.buttons["Save Current Settings as New Profile"]
            XCTAssertTrue(fallbackSaveCurrent.waitForExistence(timeout: 5))
            fallbackSaveCurrent.click()
        }

        let editButton = app.buttons["Edit"].firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.click()

        XCTAssertTrue(app.staticTexts["Workday"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Notifications & Enforcement"].exists)
        XCTAssertTrue(app.staticTexts["Blocklist"].exists)

        let manualBundleID = app.textFields["Manual bundle ID"]
        let fallbackManualBundleID = app.textFields.matching(NSPredicate(format: "placeholderValue == %@", "Manual bundle ID")).firstMatch
        XCTAssertTrue(manualBundleID.exists || fallbackManualBundleID.exists)
    }

    private func launch(arguments: [String] = ["--uitesting"]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
    }

    private func openSidebarItem(accessibilityID: String, fallbackLabel: String) {
        let identifiedButton = app.buttons[accessibilityID]
        if identifiedButton.waitForExistence(timeout: 5) {
            identifiedButton.click()
            return
        }

        let identifiedStaticText = app.staticTexts[accessibilityID]
        if identifiedStaticText.waitForExistence(timeout: 2) {
            identifiedStaticText.click()
            return
        }

        let fallbackButton = app.buttons[fallbackLabel]
        if fallbackButton.waitForExistence(timeout: 2) {
            fallbackButton.click()
            return
        }

        let fallbackStaticText = app.staticTexts[fallbackLabel]
        XCTAssertTrue(fallbackStaticText.waitForExistence(timeout: 2), "Missing sidebar item \(fallbackLabel)")
        fallbackStaticText.click()
    }
}
