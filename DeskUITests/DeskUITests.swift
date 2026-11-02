import XCTest

/// Interaction smoke tests driven through real system events. Each test gets its own
/// scratch store so the planner's real data is never touched.
final class DeskUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // A throwaway store inside the app's sandbox container, unique per test.
        app.launchEnvironment["DESK_SCRATCH_STORE"] = "uitest-\(UUID().uuidString)"
        app.launchEnvironment["DESK_WINDOW_SIZE"] = "1440x900"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: Helpers

    /// Screen point in the first day column at a given hour (06:00–22:00 rendered range).
    private func point(hour: Double, in column: XCUIElement, xFraction: CGFloat = 0.5) -> XCUICoordinate {
        let f = column.frame
        let y = f.minY + CGFloat((hour - 6) / 16) * f.height
        return screenPoint(CGPoint(x: f.minX + f.width * xFraction, y: y))
    }

    /// The application element has no frame on macOS, so coordinates are anchored to the window.
    private func screenPoint(_ p: CGPoint) -> XCUICoordinate {
        let window = app.windows.firstMatch
        let wf = window.frame
        return window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: p.x - wf.minX, dy: p.y - wf.minY))
    }

    private var column: XCUIElement {
        let c = app.otherElements["timeline.column.0"].firstMatch
        XCTAssertTrue(c.waitForExistence(timeout: 5), "day column should exist")
        return c
    }

    private func block(_ title: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "block.\(title)").firstMatch
    }

    /// Clicks empty grid space (ends any text editing) after waiting for popovers and sheets
    /// to finish dismissing, so the next keystroke reaches the planner, not a closing overlay.
    private func clickEmptyGrid() {
        _ = waitUntil(timeout: 5) { !self.app.sheets.firstMatch.exists && !self.app.popovers.firstMatch.exists }
        point(hour: 21.5, in: column).click()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    // MARK: Tests

    func testDragCreateThenMoveThenResize() throws {
        // Work on tomorrow so today's current-time line never interferes.
        app.buttons["toolbar.tomorrow"].click()
        let col = column

        // Drag 10:00 → 11:30 creates a block and opens its editor.
        point(hour: 10, in: col).click(forDuration: 0.1, thenDragTo: point(hour: 11.5, in: col))
        let title = app.textFields["blockEditor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5), "editor should open after drag-create")
        title.typeText("Deep work\r")

        let created = block("Deep work")
        XCTAssertTrue(created.waitForExistence(timeout: 5))
        XCTAssertTrue(created.label.contains("10:00"), created.label)
        XCTAssertTrue(created.label.contains("11:30"), created.label)

        // Move it two hours later.
        created.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .click(forDuration: 0.2, thenDragTo: point(hour: 12.6, in: col))
        let moved = block("Deep work")
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        let movedLabel = waitForLabel(moved, containing: "12:00")
        XCTAssertTrue(movedLabel.contains("1:30"), movedLabel)

        // Resize the bottom edge to 14:00.
        let bottom = moved.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        bottom.click(forDuration: 0.2, thenDragTo: point(hour: 14, in: col))
        let resizedLabel = waitForLabel(block("Deep work"), containing: " 2:")   // ends around 14:00 (±15 min snap)
        XCTAssertTrue(resizedLabel.contains("12:00"), resizedLabel)

        // Undo twice (focus is on the grid, so ⌘Z is block history, not text).
        clickEmptyGrid()
        app.typeKey("z", modifierFlags: .command)
        _ = waitForLabel(block("Deep work"), containing: "1:30")
        app.typeKey("z", modifierFlags: .command)
        let undone = waitForLabel(block("Deep work"), containing: "10:00")
        XCTAssertTrue(undone.contains("11:30"), undone)
    }

    func testLetterShortcutsNeverTypeIntoNotes() throws {
        clickEmptyGrid()
        app.typeKey("w", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["weekHeading"].waitForExistence(timeout: 3), "W should switch to Week")
        app.typeKey("d", modifierFlags: [])
        XCTAssertTrue(app.staticTexts["dateHeading"].waitForExistence(timeout: 3), "D should switch to Day")
        let heading = app.staticTexts["dateHeading"].label
        app.typeKey("k", modifierFlags: [])
        XCTAssertTrue(waitUntil { self.app.staticTexts["dateHeading"].label != heading }, "K should go to the next day")
        app.typeKey("t", modifierFlags: [])
        XCTAssertTrue(waitUntil { self.app.staticTexts["dateHeading"].label == heading }, "T should return to today")

        // B focuses the brain dump; letters are then plain characters.
        app.typeKey("b", modifierFlags: [])
        let notes = app.textViews["brainDump"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 3))
        app.typeText("tn jk wd\n\tindented line")
        XCTAssertTrue(waitUntil { (notes.value as? String)?.contains("tn jk wd") == true })
        XCTAssertEqual(app.staticTexts["dateHeading"].label, heading, "typing letters must not navigate")
        XCTAssertTrue((notes.value as? String)?.contains("\tindented") == true)
    }

    func testNotesAndPrioritiesSurviveNavigationAndRelaunch() throws {
        let p1 = app.textFields["priority.1"].firstMatch
        XCTAssertTrue(p1.waitForExistence(timeout: 5))
        p1.click()
        app.typeText("Ship it\r")            // Return moves to priority 2
        app.typeText("Call mom\r")
        app.typeText("Walk\r")               // Return on the last row adds a 4th
        app.typeText("Read")
        XCTAssertTrue(app.textFields["priority.4"].waitForExistence(timeout: 3))

        let notes = app.textViews["brainDump"].firstMatch
        notes.click()
        app.typeText("First thought\n\n\tNested idea\n    four spaces")

        // Navigate away and back quickly; nothing may be lost.
        clickEmptyGrid()
        app.typeKey("k", modifierFlags: [])
        app.typeKey("k", modifierFlags: [])
        app.typeKey("j", modifierFlags: [])
        app.typeKey("j", modifierFlags: [])
        XCTAssertTrue(waitUntil { (self.app.textFields["priority.1"].firstMatch.value as? String) == "Ship it" })
        XCTAssertEqual(app.textFields["priority.4"].firstMatch.value as? String, "Read")
        XCTAssertTrue((app.textViews["brainDump"].firstMatch.value as? String)?.contains("\tNested idea\n    four spaces") == true)

        // Relaunch with the same store.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.textFields["priority.1"].waitForExistence(timeout: 10))
        XCTAssertTrue(waitUntil { (self.app.textFields["priority.1"].firstMatch.value as? String) == "Ship it" })
        XCTAssertEqual(app.textFields["priority.3"].firstMatch.value as? String, "Walk")
        XCTAssertEqual(app.textFields["priority.4"].firstMatch.value as? String, "Read")
        XCTAssertTrue((app.textViews["brainDump"].firstMatch.value as? String)?.contains("First thought\n\n\tNested idea") == true)
    }

    func testBlockCreatedInWeekAppearsInDay() throws {
        clickEmptyGrid()
        app.typeKey("a", modifierFlags: [])   // Add block on the selected day
        let title = app.textFields["blockEditor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Shared block\r")
        XCTAssertTrue(block("Shared block").waitForExistence(timeout: 5))
        clickEmptyGrid()
        app.typeKey("w", modifierFlags: [])
        XCTAssertTrue(block("Shared block").waitForExistence(timeout: 5), "block should be visible in Week")
        app.typeKey("d", modifierFlags: [])
        XCTAssertTrue(block("Shared block").waitForExistence(timeout: 5), "block should be visible in Day")
    }

    func testRecurringRoutineAndScopePrompt() throws {
        app.buttons["toolbar.tomorrow"].click()
        let col = column
        point(hour: 7, in: col).click(forDuration: 0.1, thenDragTo: point(hour: 8, in: col))
        let title = app.textFields["blockEditor.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Gym")
        // Repeat on every day of the week via the weekday toggles.
        for day in ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"] {
            app.buttons[day].firstMatch.click()
        }
        app.buttons["Done"].firstMatch.click()
        let gym = block("Gym")
        XCTAssertTrue(gym.waitForExistence(timeout: 5))
        XCTAssertTrue(gym.label.contains("repeats weekly"), gym.label)

        // Next week has it too.
        clickEmptyGrid()
        app.typeKey("k", modifierFlags: [])
        for _ in 0..<6 { app.typeKey("k", modifierFlags: []) }
        XCTAssertTrue(block("Gym").waitForExistence(timeout: 5), "routine should appear a week later")

        // Dragging a recurring block asks for a scope; choosing This Occurrence leaves the series alone.
        block("Gym").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .click(forDuration: 0.2, thenDragTo: point(hour: 9.6, in: col))
        let thisOccurrence = app.sheets.firstMatch.buttons["This Occurrence"].firstMatch
        XCTAssertTrue(thisOccurrence.waitForExistence(timeout: 5), "scope prompt should appear")
        thisOccurrence.click()
        _ = waitForLabel(block("Gym"), containing: "9:")   // moved later and snapped to 15 minutes
        clickEmptyGrid()
        app.typeKey("j", modifierFlags: [])
        let previousDay = waitForLabel(block("Gym"), containing: "7:00")
        XCTAssertTrue(previousDay.contains("8:00"), previousDay)
    }

    // MARK: Waiting

    @discardableResult
    private func waitForLabel(_ element: XCUIElement, containing text: String, timeout: TimeInterval = 5) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var label = ""
        while Date() < deadline {
            if element.exists { label = element.label; if label.contains(text) { return label } }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("expected label containing \(text), got \(label)")
        return label
    }

    private func waitUntil(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }
}
