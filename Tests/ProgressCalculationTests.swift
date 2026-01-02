import XCTest
@testable import Crux

final class ProgressCalculationTests: XCTestCase {

    // MARK: - Book Progress Formula Tests

    /// Tests the book progress calculation: chapterProgress + withinChapterProgress
    /// Formula: (currentChapter / totalChapters) + (scrollPosition / totalChapters)

    func testBookProgressAtStart() {
        let progress = calculateBookProgress(
            currentChapter: 0,
            totalChapters: 10,
            scrollPosition: 0.0
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }

    func testBookProgressAtEnd() {
        let progress = calculateBookProgress(
            currentChapter: 9,
            totalChapters: 10,
            scrollPosition: 1.0
        )
        XCTAssertEqual(progress, 1.0, accuracy: 0.001)
    }

    func testBookProgressMidBook() {
        // Chapter 5 of 10 (50% chapter progress) with 0% scroll
        let progress = calculateBookProgress(
            currentChapter: 5,
            totalChapters: 10,
            scrollPosition: 0.0
        )
        XCTAssertEqual(progress, 0.5, accuracy: 0.001)
    }

    func testBookProgressWithScroll() {
        // Chapter 0 of 10 with 50% scroll = 5% overall
        let progress = calculateBookProgress(
            currentChapter: 0,
            totalChapters: 10,
            scrollPosition: 0.5
        )
        XCTAssertEqual(progress, 0.05, accuracy: 0.001)
    }

    func testBookProgressMidChapterMidBook() {
        // Chapter 4 of 10 (40%) with 50% scroll (+5%) = 45%
        let progress = calculateBookProgress(
            currentChapter: 4,
            totalChapters: 10,
            scrollPosition: 0.5
        )
        XCTAssertEqual(progress, 0.45, accuracy: 0.001)
    }

    func testBookProgressSingleChapter() {
        // Edge case: single chapter book
        let progressStart = calculateBookProgress(
            currentChapter: 0,
            totalChapters: 1,
            scrollPosition: 0.0
        )
        XCTAssertEqual(progressStart, 0.0, accuracy: 0.001)

        let progressEnd = calculateBookProgress(
            currentChapter: 0,
            totalChapters: 1,
            scrollPosition: 1.0
        )
        XCTAssertEqual(progressEnd, 1.0, accuracy: 0.001)
    }

    func testBookProgressEmptyChapters() {
        // Edge case: no chapters (should handle gracefully)
        let progress = calculateBookProgress(
            currentChapter: 0,
            totalChapters: 0,
            scrollPosition: 0.5
        )
        XCTAssertEqual(progress, 0.0, accuracy: 0.001)
    }

    // MARK: - Percentage Calculation Tests

    func testChapterPercentageAtStart() {
        let percentage = calculateChapterPercentage(scrollPosition: 0.0)
        XCTAssertEqual(percentage, 0)
    }

    func testChapterPercentageAtEnd() {
        let percentage = calculateChapterPercentage(scrollPosition: 1.0)
        XCTAssertEqual(percentage, 100)
    }

    func testChapterPercentageMidway() {
        let percentage = calculateChapterPercentage(scrollPosition: 0.42)
        XCTAssertEqual(percentage, 42)
    }

    func testChapterPercentageRounding() {
        // 0.999 should round to 99 (Int truncation)
        let percentage = calculateChapterPercentage(scrollPosition: 0.999)
        XCTAssertEqual(percentage, 99)
    }

    func testOverallPercentage() {
        // Chapter 2 of 5 (40%) + 50% scroll in chapter (+10%) = 50%
        let percentage = calculateOverallPercentage(
            currentChapter: 2,
            totalChapters: 5,
            scrollPosition: 0.5
        )
        XCTAssertEqual(percentage, 50)
    }

    // MARK: - StoredBook Progress Tests

    func testStoredBookProgressUpdate() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 10)

        book.updateProgress(chapter: 5, total: 10, scroll: 0.5)

        XCTAssertEqual(book.currentChapterIndex, 5)
        XCTAssertEqual(book.scrollPosition, 0.5, accuracy: 0.001)
        XCTAssertEqual(book.totalChapters, 10)
    }

    func testStoredBookNotFinishedMidBook() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 10)

        book.updateProgress(chapter: 5, total: 10, scroll: 0.99)

        XCTAssertFalse(book.isFinished)
    }

    func testStoredBookNotFinishedLastChapterStart() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 10)

        book.updateProgress(chapter: 9, total: 10, scroll: 0.5)

        XCTAssertFalse(book.isFinished)
    }

    func testStoredBookFinishedLastChapterEnd() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 10)

        book.updateProgress(chapter: 9, total: 10, scroll: 0.95)

        XCTAssertTrue(book.isFinished)
    }

    func testStoredBookFinishedExactly90Percent() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 10)

        // At exactly 90% - should NOT be finished (needs > 0.9)
        book.updateProgress(chapter: 9, total: 10, scroll: 0.9)
        XCTAssertFalse(book.isFinished)

        // Just over 90% - should be finished
        book.updateProgress(chapter: 9, total: 10, scroll: 0.91)
        XCTAssertTrue(book.isFinished)
    }

    func testStoredBookFinishedSingleChapter() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 1)

        book.updateProgress(chapter: 0, total: 1, scroll: 0.95)

        XCTAssertTrue(book.isFinished)
    }

    func testStoredBookLastOpenedUpdates() {
        let book = StoredBook(id: UUID(), title: "Test", totalChapters: 10)
        let originalDate = book.lastOpenedAt ?? Date.distantPast

        Foundation.Thread.sleep(forTimeInterval: 0.01)
        book.markOpened()

        XCTAssertGreaterThan(book.lastOpenedAt ?? Date.distantPast, originalDate)
    }

    // MARK: - Helper Functions

    /// Replicates the book progress calculation from ReaderView
    private func calculateBookProgress(
        currentChapter: Int,
        totalChapters: Int,
        scrollPosition: Double
    ) -> Double {
        guard totalChapters > 0 else { return 0 }
        let chapterProgress = Double(currentChapter) / Double(totalChapters)
        let withinChapterProgress = scrollPosition / Double(totalChapters)
        return chapterProgress + withinChapterProgress
    }

    /// Replicates chapter percentage calculation
    private func calculateChapterPercentage(scrollPosition: Double) -> Int {
        Int(scrollPosition * 100)
    }

    /// Replicates overall percentage calculation
    private func calculateOverallPercentage(
        currentChapter: Int,
        totalChapters: Int,
        scrollPosition: Double
    ) -> Int {
        let progress = calculateBookProgress(
            currentChapter: currentChapter,
            totalChapters: totalChapters,
            scrollPosition: scrollPosition
        )
        return Int(progress * 100)
    }
}
