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
        clickElement(accessibilityID: "onboarding.preset.writerGentleRoutine", fallbackLabel: "Writer Gentle Routine")
        clickElement(accessibilityID: "onboarding.continue", fallbackLabel: "Continue")

        XCTAssertTrue(app.staticTexts["Enable essential permissions"].waitForExistence(timeout: 5))
    }

    func testOnboardingAgentDeveloperPresetPath() throws {
        launch(arguments: ["--uitesting", "--reset-onboarding"])

        XCTAssertTrue(app.staticTexts["Choose a working style"].waitForExistence(timeout: 5))
        clickElement(accessibilityID: "onboarding.preset.agentDeveloper", fallbackLabel: "Agent Developer")
        clickElement(accessibilityID: "onboarding.continue", fallbackLabel: "Continue")

        XCTAssertTrue(app.staticTexts["Enable essential permissions"].waitForExistence(timeout: 5))
    }

    func testSettingsScreenShowsSyncAndTransferSections() throws {
        launch()
        openSidebarItem(accessibilityID: "sidebar.settings", fallbackLabel: "Settings")

        XCTAssertTrue(waitForElement(accessibilityID: "settings.export", fallbackLabel: "Export Settings", timeout: 5).exists)
        XCTAssertTrue(waitForElement(accessibilityID: "settings.import", fallbackLabel: "Import Settings", timeout: 2).exists)
    }

    func testSettingsDiagnosticsPanelRefreshAndClearFlow() throws {
        launch()
        openSidebarItem(accessibilityID: "sidebar.settings", fallbackLabel: "Settings")

        XCTAssertTrue(app.staticTexts["Recent events"].waitForExistence(timeout: 5))

        let refreshButton = waitForElement(
            accessibilityID: "Refresh Diagnostics",
            fallbackLabel: "Refresh Diagnostics",
            timeout: 5
        )
        XCTAssertTrue(refreshButton.exists)
        activateApp()
        refreshButton.click()

        let clearButton = waitForElement(
            accessibilityID: "Clear Diagnostics",
            fallbackLabel: "Clear Diagnostics",
            timeout: 5
        )
        XCTAssertTrue(clearButton.exists)
        activateApp()
        clearButton.click()

        XCTAssertTrue(app.staticTexts["Recent events"].waitForExistence(timeout: 5))
    }

    func testProfileEditorBootstrapAgentPresetsFlow() throws {
        launch()
        openSidebarItem(accessibilityID: "sidebar.profiles", fallbackLabel: "Profiles")
        clickElement(accessibilityID: "profiles.bootstrapAgentPresets", fallbackLabel: "Bootstrap Agent Presets")

        let addedMessage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Added")).firstMatch
        let alreadyExistsMessage = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "already exist")).firstMatch
        XCTAssertTrue(addedMessage.waitForExistence(timeout: 5) || alreadyExistsMessage.waitForExistence(timeout: 2))
    }

    func testProfileEditorShowsFullRoutineControls() throws {
        launch()
        openSidebarItem(accessibilityID: "sidebar.profiles", fallbackLabel: "Profiles")

        clickElement(accessibilityID: "profiles.saveCurrent", fallbackLabel: "Save Current Settings as New Profile")

        let editButton = waitForElement(accessibilityID: "profiles.edit", fallbackLabel: "Edit", timeout: 5)
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        activateApp()
        editButton.click()

        XCTAssertTrue(waitForElement(accessibilityID: "profile.jump.workday", fallbackLabel: "Workday", timeout: 5).exists)
        XCTAssertTrue(waitForElement(accessibilityID: "profile.jump.notifications", fallbackLabel: "Enforcement", timeout: 2).exists)
        XCTAssertTrue(waitForElement(accessibilityID: "profile.jump.blocklist", fallbackLabel: "Blocklist", timeout: 2).exists)
    }

    private func launch(arguments: [String] = ["--uitesting"]) {
        app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        activateApp()
    }

    private func openSidebarItem(accessibilityID: String, fallbackLabel: String) {
        let identifiedButton = app.buttons[accessibilityID]
        if identifiedButton.waitForExistence(timeout: 5) {
            activateApp()
            identifiedButton.click()
            return
        }

        let identifiedStaticText = app.staticTexts[accessibilityID]
        if identifiedStaticText.waitForExistence(timeout: 2) {
            activateApp()
            identifiedStaticText.click()
            return
        }

        let fallbackButton = app.buttons[fallbackLabel]
        if fallbackButton.waitForExistence(timeout: 2) {
            activateApp()
            fallbackButton.click()
            return
        }

        let fallbackStaticText = app.staticTexts[fallbackLabel]
        XCTAssertTrue(fallbackStaticText.waitForExistence(timeout: 2), "Missing sidebar item \(fallbackLabel)")
        activateApp()
        fallbackStaticText.click()
    }

    private func clickElement(accessibilityID: String, fallbackLabel: String) {
        let element = waitForElement(accessibilityID: accessibilityID, fallbackLabel: fallbackLabel, timeout: 5)
        XCTAssertTrue(element.exists, "Missing element \(fallbackLabel)")
        activateApp()
        element.click()
    }

    private func waitForElement(
        accessibilityID: String,
        fallbackLabel: String,
        timeout: TimeInterval
    ) -> XCUIElement {
        let identified = app.descendants(matching: .any)[accessibilityID]
        if identified.waitForExistence(timeout: timeout) {
            return identified
        }

        let fallbacks: [XCUIElement] = [
            app.buttons[fallbackLabel],
            app.popUpButtons[fallbackLabel],
            app.textFields[fallbackLabel],
            app.staticTexts[fallbackLabel],
            app.otherElements[fallbackLabel],
        ]

        for element in fallbacks where element.waitForExistence(timeout: 1) {
            return element
        }

        return identified
    }

    private func activateApp() {
        app.activate()
    }
}
