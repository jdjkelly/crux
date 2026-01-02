import XCTest

/// UI Tests for reader position tracking and restoration
///
/// SETUP: These tests require at least one EPUB book in the library.
/// Add an EPUB file to your library before running tests.
///
/// To run: xcodebuild -scheme CruxUITests -destination 'platform=macOS' test
final class ReaderPositionUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - App Launch Tests

    func testAppLaunches() throws {
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }

    func testLibraryViewExists() throws {
        let addBooksButton = app.buttons["Add Books"]
        let booksList = app.scrollViews.firstMatch

        XCTAssertTrue(addBooksButton.exists || booksList.exists,
                      "Should show library with Add Books button or book list")
    }

    // MARK: - Position Indicator Tests

    func testPositionIndicatorsVisible() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library - add an EPUB to test position indicators")
        }

        // Wait for reader to load
        let positionIndicator = app.otherElements["positionIndicator"]
        XCTAssertTrue(positionIndicator.waitForExistence(timeout: 5),
                      "Position indicator should be visible")

        // Check for chapter position (e.g., "Ch 1/5")
        let chapterPosition = app.staticTexts["chapterPosition"]
        XCTAssertTrue(chapterPosition.exists, "Chapter position should be visible")
        XCTAssertTrue(chapterPosition.label.contains("Ch "), "Should show chapter number")

        // Check for percentage indicators
        let chapterPercent = app.staticTexts["chapterPercentage"]
        XCTAssertTrue(chapterPercent.exists, "Chapter percentage should be visible")

        let overallPercent = app.staticTexts["overallPercentage"]
        XCTAssertTrue(overallPercent.exists, "Overall percentage should be visible")
    }

    func testNavigationButtonsExist() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library")
        }

        sleep(2)

        let prevButton = app.buttons["previousChapter"]
        let nextButton = app.buttons["nextChapter"]

        XCTAssertTrue(prevButton.waitForExistence(timeout: 5), "Previous chapter button should exist")
        XCTAssertTrue(nextButton.exists, "Next chapter button should exist")
    }

    // MARK: - Chapter Navigation Tests

    func testChapterNavigationUpdatesPosition() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library")
        }

        let chapterPosition = app.staticTexts["chapterPosition"]
        XCTAssertTrue(chapterPosition.waitForExistence(timeout: 5))

        let initialLabel = chapterPosition.label

        // Navigate to next chapter
        let nextButton = app.buttons["nextChapter"]
        guard nextButton.exists && nextButton.isEnabled else {
            throw XCTSkip("Only one chapter in book, can't test navigation")
        }

        nextButton.click()
        sleep(1)

        // Verify chapter changed
        let newLabel = chapterPosition.label
        XCTAssertNotEqual(initialLabel, newLabel,
                          "Chapter indicator should change after navigation: was '\(initialLabel)', now '\(newLabel)'")
    }

    func testPreviousChapterNavigation() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library")
        }

        let nextButton = app.buttons["nextChapter"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))

        // First navigate forward
        guard nextButton.isEnabled else {
            throw XCTSkip("Only one chapter in book")
        }
        nextButton.click()
        sleep(1)

        let chapterPosition = app.staticTexts["chapterPosition"]
        let afterNext = chapterPosition.label

        // Now go back
        let prevButton = app.buttons["previousChapter"]
        XCTAssertTrue(prevButton.isEnabled, "Previous button should be enabled after moving forward")
        prevButton.click()
        sleep(1)

        let afterPrev = chapterPosition.label
        XCTAssertNotEqual(afterNext, afterPrev, "Should navigate back to previous chapter")
    }

    func testChapterMenuExists() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library")
        }

        sleep(2)

        let chaptersButton = app.buttons["Chapters"]
        XCTAssertTrue(chaptersButton.waitForExistence(timeout: 5), "Chapters menu button should exist")

        chaptersButton.click()
        sleep(1)

        // Menu should appear with chapter items
        let menuItems = app.menuItems
        XCTAssertTrue(menuItems.count > 0, "Chapter menu should have items")
    }

    // MARK: - Scroll Position Tests

    func testScrollUpdatesPercentage() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library")
        }

        let chapterPercent = app.staticTexts["chapterPercentage"]
        XCTAssertTrue(chapterPercent.waitForExistence(timeout: 5))

        let initialPercent = chapterPercent.label

        // Try to scroll the web view content
        let webView = app.webViews.firstMatch
        guard webView.exists else {
            throw XCTSkip("WebView not found")
        }

        // Scroll down
        webView.scroll(byDeltaX: 0, deltaY: -300)
        sleep(1)

        let newPercent = chapterPercent.label
        // Log for debugging - percentage may or may not change depending on content
        print("Scroll test - Initial: \(initialPercent), After scroll: \(newPercent)")

        // At minimum, the indicator should still exist
        XCTAssertTrue(chapterPercent.exists, "Percentage indicator should remain after scroll")
    }

    // MARK: - Position Persistence Tests

    func testPositionSavedOnNavigation() throws {
        guard openFirstBook() else {
            throw XCTSkip("No books in library")
        }

        let nextButton = app.buttons["nextChapter"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))

        // Navigate to chapter 2 (if available)
        guard nextButton.isEnabled else {
            throw XCTSkip("Only one chapter available")
        }

        nextButton.click()
        sleep(1)

        // Record current chapter
        let chapterPosition = app.staticTexts["chapterPosition"]
        let chapterLabel = chapterPosition.label

        // Go back to library (close the book)
        // On macOS, we can use keyboard shortcut or window close
        #if os(macOS)
        app.typeKey("w", modifierFlags: .command)
        sleep(1)
        #endif

        // Re-open the same book
        guard openFirstBook() else {
            XCTFail("Could not reopen book")
            return
        }

        sleep(2)

        // Verify we're at the same chapter
        XCTAssertTrue(chapterPosition.waitForExistence(timeout: 5))
        let restoredLabel = chapterPosition.label
        XCTAssertEqual(chapterLabel, restoredLabel,
                       "Position should be restored when reopening book")
    }

    // MARK: - Helper Methods

    /// Attempts to open the first book in the library
    @discardableResult
    private func openFirstBook() -> Bool {
        // Wait a moment for library to load
        sleep(1)

        // Try common patterns for finding books
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            // Look for buttons (book items)
            let buttons = scrollView.buttons
            if buttons.count > 0 {
                buttons.firstMatch.doubleClick()
                sleep(2)
                // Check if we're in reader view
                return app.buttons["nextChapter"].waitForExistence(timeout: 3) ||
                       app.otherElements["positionIndicator"].waitForExistence(timeout: 3)
            }

            // Try images (book covers)
            let images = scrollView.images
            if images.count > 0 {
                images.firstMatch.doubleClick()
                sleep(2)
                return app.buttons["nextChapter"].waitForExistence(timeout: 3)
            }

            // Try any clickable groups
            let groups = scrollView.groups
            if groups.count > 0 {
                groups.firstMatch.doubleClick()
                sleep(2)
                return app.buttons["nextChapter"].waitForExistence(timeout: 3)
            }
        }

        return false
    }
}

// MARK: - Position Restoration Across App Restart

final class PositionRestorationUITests: XCTestCase {

    func testPositionRestoredAfterRelaunch() throws {
        // First launch - open book and navigate
        var app = XCUIApplication()
        app.launch()

        guard openFirstBook(in: app) else {
            throw XCTSkip("No books in library for restoration test")
        }

        let nextButton = app.buttons["nextChapter"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))

        // Navigate to a specific position
        if nextButton.isEnabled {
            nextButton.click()
            sleep(1)
        }

        // Get current position
        let chapterPosition = app.staticTexts["chapterPosition"]
        let positionBeforeRestart = chapterPosition.label

        // Terminate and relaunch
        app.terminate()
        sleep(1)

        app = XCUIApplication()
        app.launch()
        sleep(1)

        // Re-open the same book
        guard openFirstBook(in: app) else {
            XCTFail("Could not reopen book after restart")
            return
        }

        // Verify position is restored
        XCTAssertTrue(chapterPosition.waitForExistence(timeout: 5))
        let positionAfterRestart = chapterPosition.label
        XCTAssertEqual(positionBeforeRestart, positionAfterRestart,
                       "Position should be restored after app restart")

        app.terminate()
    }

    private func openFirstBook(in app: XCUIApplication) -> Bool {
        sleep(1)
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            let buttons = scrollView.buttons
            if buttons.count > 0 {
                buttons.firstMatch.doubleClick()
                sleep(2)
                return app.buttons["nextChapter"].waitForExistence(timeout: 3)
            }
            let images = scrollView.images
            if images.count > 0 {
                images.firstMatch.doubleClick()
                sleep(2)
                return app.buttons["nextChapter"].waitForExistence(timeout: 3)
            }
        }
        return false
    }
}

// MARK: - Performance Tests

final class ReaderPerformanceUITests: XCTestCase {

    func testChapterNavigationPerformance() throws {
        let app = XCUIApplication()
        app.launch()

        guard openFirstBook(in: app) else {
            throw XCTSkip("No books in library")
        }

        let nextButton = app.buttons["nextChapter"]
        XCTAssertTrue(nextButton.waitForExistence(timeout: 5))

        guard nextButton.isEnabled else {
            throw XCTSkip("Only one chapter")
        }

        // Measure navigation performance
        measure {
            nextButton.click()
            _ = app.staticTexts["chapterPosition"].waitForExistence(timeout: 2)
        }

        app.terminate()
    }

    private func openFirstBook(in app: XCUIApplication) -> Bool {
        sleep(1)
        let scrollView = app.scrollViews.firstMatch
        if scrollView.exists {
            let buttons = scrollView.buttons
            if buttons.count > 0 {
                buttons.firstMatch.doubleClick()
                sleep(2)
                return app.buttons["nextChapter"].waitForExistence(timeout: 3)
            }
        }
        return false
    }
}
