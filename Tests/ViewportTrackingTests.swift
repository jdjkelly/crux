import XCTest
@testable import Crux

final class ViewportTrackingTests: XCTestCase {

    // MARK: - Chapter Model Tests

    func testChapterFilePathExtraction() {
        let chapter = Chapter(
            id: "ch1",
            title: "Chapter 1",
            href: "content.xhtml#section-1",
            order: 0
        )

        XCTAssertEqual(chapter.filePath, "content.xhtml")
        XCTAssertEqual(chapter.fragment, "section-1")
    }

    func testChapterWithoutFragment() {
        let chapter = Chapter(
            id: "ch1",
            title: "Chapter 1",
            href: "content.xhtml",
            order: 0
        )

        XCTAssertEqual(chapter.filePath, "content.xhtml")
        XCTAssertNil(chapter.fragment)
    }

    // MARK: - Anchor Mapping Tests

    func testAnchorMappingForChaptersWithFragments() {
        // Given chapters with fragments pointing to same file
        let chapters = [
            Chapter(id: "ch1", title: "Chapter 1", href: "content.xhtml", order: 0),
            Chapter(id: "ch1-1", title: "Section 1", href: "content.xhtml#section-1", order: 1, depth: 1),
            Chapter(id: "ch1-2", title: "Section 2", href: "content.xhtml#section-2", order: 2, depth: 1),
        ]

        // When building anchor map for content.xhtml
        let anchors = buildAnchorMap(chapters: chapters, filePath: "content.xhtml")

        // Then should have 3 entries (doc start + 2 fragments)
        XCTAssertEqual(anchors.count, 3)

        // Verify doc start entry
        let docStart = anchors.first { $0.id == "__crux_doc_start__" }
        XCTAssertNotNil(docStart)
        XCTAssertEqual(docStart?.chapterIndex, 0)
        XCTAssertTrue(docStart?.isFileStart ?? false)

        // Verify fragment entries
        let section1 = anchors.first { $0.id == "section-1" }
        XCTAssertNotNil(section1)
        XCTAssertEqual(section1?.chapterIndex, 1)
        XCTAssertFalse(section1?.isFileStart ?? true)

        let section2 = anchors.first { $0.id == "section-2" }
        XCTAssertNotNil(section2)
        XCTAssertEqual(section2?.chapterIndex, 2)
        XCTAssertFalse(section2?.isFileStart ?? true)
    }

    func testAnchorMappingExcludesDifferentFiles() {
        let chapters = [
            Chapter(id: "ch1", title: "Chapter 1", href: "chapter1.xhtml", order: 0),
            Chapter(id: "ch2", title: "Chapter 2", href: "chapter2.xhtml", order: 1),
        ]

        let anchors = buildAnchorMap(chapters: chapters, filePath: "chapter1.xhtml")

        XCTAssertEqual(anchors.count, 1)
        XCTAssertEqual(anchors[0].chapterIndex, 0)
    }

    func testAnchorMappingForMultipleChaptersWithoutFragments() {
        // Edge case: Two chapters pointing to same file without fragments
        // Only one doc start should be created (for first chapter)
        let chapters = [
            Chapter(id: "ch1", title: "Chapter 1", href: "content.xhtml", order: 0),
            Chapter(id: "ch2", title: "Chapter 2", href: "content.xhtml", order: 1),  // Unusual but possible
        ]

        let anchors = buildAnchorMap(chapters: chapters, filePath: "content.xhtml")

        // Both chapters should get doc start entries with different indices
        XCTAssertEqual(anchors.count, 2)
        XCTAssertTrue(anchors.allSatisfy { $0.id == "__crux_doc_start__" })
    }

    // MARK: - Navigation Guard Tests

    func testNavigationGuardPreventsUpdatesDuringNavigation() {
        var updatedIndex: Int? = nil
        let handler = createVisibleSectionHandler(
            isNavigating: true,
            currentIndex: 0,
            chapterCount: 10,
            onUpdate: { updatedIndex = $0 }
        )

        handler(5)

        XCTAssertNil(updatedIndex, "Should not update during navigation")
    }

    func testNavigationGuardAllowsUpdatesWhenNotNavigating() {
        var updatedIndex: Int? = nil
        let handler = createVisibleSectionHandler(
            isNavigating: false,
            currentIndex: 0,
            chapterCount: 10,
            onUpdate: { updatedIndex = $0 }
        )

        handler(5)

        XCTAssertEqual(updatedIndex, 5)
    }

    func testNoUpdateWhenIndexUnchanged() {
        var updateCount = 0
        let handler = createVisibleSectionHandler(
            isNavigating: false,
            currentIndex: 3,
            chapterCount: 10,
            onUpdate: { _ in updateCount += 1 }
        )

        handler(3)

        XCTAssertEqual(updateCount, 0, "Should not update when index unchanged")
    }

    func testRejectsInvalidIndex() {
        var updatedIndex: Int? = nil
        let handler = createVisibleSectionHandler(
            isNavigating: false,
            currentIndex: 0,
            chapterCount: 5,
            onUpdate: { updatedIndex = $0 }
        )

        // Test negative index
        handler(-1)
        XCTAssertNil(updatedIndex, "Should reject negative index")

        // Test out of bounds index
        handler(10)
        XCTAssertNil(updatedIndex, "Should reject out of bounds index")
    }

    // MARK: - Helper Types and Functions

    struct AnchorData {
        let id: String
        let chapterIndex: Int
        let isFileStart: Bool
    }

    func buildAnchorMap(chapters: [Chapter], filePath: String) -> [AnchorData] {
        var anchors: [AnchorData] = []

        for (index, chapter) in chapters.enumerated() {
            guard chapter.filePath == filePath else { continue }

            if let fragment = chapter.fragment {
                anchors.append(AnchorData(id: fragment, chapterIndex: index, isFileStart: false))
            } else {
                anchors.append(AnchorData(id: "__crux_doc_start__", chapterIndex: index, isFileStart: true))
            }
        }

        return anchors
    }

    func createVisibleSectionHandler(
        isNavigating: Bool,
        currentIndex: Int,
        chapterCount: Int,
        onUpdate: @escaping (Int) -> Void
    ) -> (Int) -> Void {
        return { chapterIndex in
            // Guard against feedback loops during programmatic navigation
            guard !isNavigating else { return }
            // No update needed if index hasn't changed
            guard chapterIndex != currentIndex else { return }
            // Validate index
            guard chapterIndex >= 0 && chapterIndex < chapterCount else { return }

            onUpdate(chapterIndex)
        }
    }
}
