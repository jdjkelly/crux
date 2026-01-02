import XCTest
@testable import Crux

// Alias to avoid conflict with Foundation.Thread
typealias AnnotationThread = Crux.Thread

final class AnnotationsTests: XCTestCase {

    // MARK: - CFIRange Tests

    func testCFIRangeInit() {
        let cfi = CFIRange(
            startPath: "/4/2/1",
            startOffset: 10,
            endPath: "/4/2/1",
            endOffset: 25
        )

        XCTAssertEqual(cfi.startPath, "/4/2/1")
        XCTAssertEqual(cfi.startOffset, 10)
        XCTAssertEqual(cfi.endPath, "/4/2/1")
        XCTAssertEqual(cfi.endOffset, 25)
    }

    func testCFIRangeCFIString() {
        let cfi = CFIRange(
            startPath: "/4/2/1",
            startOffset: 10,
            endPath: "/4/2/3",
            endOffset: 5
        )

        XCTAssertEqual(cfi.cfiString, "/4/2/1:10,/4/2/3:5")
    }

    func testCFIRangeEquality() {
        let cfi1 = CFIRange(startPath: "/1", startOffset: 0, endPath: "/1", endOffset: 10)
        let cfi2 = CFIRange(startPath: "/1", startOffset: 0, endPath: "/1", endOffset: 10)
        let cfi3 = CFIRange(startPath: "/1", startOffset: 0, endPath: "/1", endOffset: 11)

        XCTAssertEqual(cfi1, cfi2)
        XCTAssertNotEqual(cfi1, cfi3)
    }

    func testCFIRangeCodable() throws {
        let original = CFIRange(
            startPath: "/4/2/1",
            startOffset: 10,
            endPath: "/4/2/3",
            endOffset: 25
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(CFIRange.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - SelectionData Tests

    func testSelectionDataEquality() {
        let cfi = CFIRange(startPath: "/1", startOffset: 0, endPath: "/1", endOffset: 10)
        let sel1 = SelectionData(text: "Hello", cfiRange: cfi, context: "Context")
        let sel2 = SelectionData(text: "Hello", cfiRange: cfi, context: "Context")
        let sel3 = SelectionData(text: "World", cfiRange: cfi, context: "Context")

        XCTAssertEqual(sel1, sel2)
        XCTAssertNotEqual(sel1, sel3)
    }

    // MARK: - Highlight Tests

    func testHighlightInit() {
        let highlight = Highlight(
            chapterId: "ch1",
            selectedText: "Test text",
            surroundingContext: "Before Test text After"
        )

        XCTAssertEqual(highlight.chapterId, "ch1")
        XCTAssertEqual(highlight.selectedText, "Test text")
        XCTAssertEqual(highlight.surroundingContext, "Before Test text After")
        XCTAssertNil(highlight.cfiRange)
        XCTAssertTrue(highlight.threads.isEmpty)
    }

    func testHighlightWithCFI() {
        let cfi = CFIRange(startPath: "/4/2", startOffset: 5, endPath: "/4/2", endOffset: 15)
        let highlight = Highlight(
            chapterId: "ch1",
            selectedText: "Test",
            surroundingContext: "Context",
            cfiRange: cfi
        )

        XCTAssertNotNil(highlight.cfiRange)
        XCTAssertEqual(highlight.cfiRange?.startPath, "/4/2")
    }

    func testHighlightIdentifiable() {
        let h1 = Highlight(chapterId: "ch1", selectedText: "A", surroundingContext: "")
        let h2 = Highlight(chapterId: "ch1", selectedText: "A", surroundingContext: "")

        // Each highlight should have unique ID
        XCTAssertNotEqual(h1.id, h2.id)
    }

    func testHighlightCodable() throws {
        let cfi = CFIRange(startPath: "/4/2", startOffset: 5, endPath: "/4/2", endOffset: 15)
        let original = Highlight(
            chapterId: "ch1",
            selectedText: "Selected",
            surroundingContext: "Context",
            cfiRange: cfi
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Highlight.self, from: data)

        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.selectedText, original.selectedText)
        XCTAssertEqual(decoded.cfiRange, original.cfiRange)
    }

    // MARK: - Thread Tests

    func testThreadInit() {
        let thread = AnnotationThread()

        XCTAssertTrue(thread.messages.isEmpty)
        XCTAssertEqual(thread.createdAt, thread.updatedAt)
    }

    func testThreadAddMessage() {
        var thread = AnnotationThread()
        let originalUpdate = thread.updatedAt

        // Small delay to ensure time difference
        Foundation.Thread.sleep(forTimeInterval: 0.01)

        let message = ThreadMessage(role: .user, content: "Hello")
        thread.addMessage(message)

        XCTAssertEqual(thread.messages.count, 1)
        XCTAssertEqual(thread.messages[0].content, "Hello")
        XCTAssertGreaterThan(thread.updatedAt, originalUpdate)
    }

    func testThreadMultipleMessages() {
        var thread = AnnotationThread()

        thread.addMessage(ThreadMessage(role: .user, content: "Question"))
        thread.addMessage(ThreadMessage(role: .assistant, content: "Answer"))
        thread.addMessage(ThreadMessage(role: .user, content: "Follow-up"))

        XCTAssertEqual(thread.messages.count, 3)
        XCTAssertEqual(thread.messages[0].role, .user)
        XCTAssertEqual(thread.messages[1].role, .assistant)
        XCTAssertEqual(thread.messages[2].role, .user)
    }

    // MARK: - ThreadMessage Tests

    func testThreadMessageInit() {
        let message = ThreadMessage(role: .assistant, content: "Response")

        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, "Response")
    }

    func testMessageRoleCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let userRole = MessageRole.user
        let assistantRole = MessageRole.assistant

        let userData = try encoder.encode(userRole)
        let assistantData = try encoder.encode(assistantRole)

        let decodedUser = try decoder.decode(MessageRole.self, from: userData)
        let decodedAssistant = try decoder.decode(MessageRole.self, from: assistantData)

        XCTAssertEqual(decodedUser, .user)
        XCTAssertEqual(decodedAssistant, .assistant)
    }

    // MARK: - BookAnnotations Tests

    func testBookAnnotationsInit() {
        let bookId = UUID()
        let annotations = BookAnnotations(bookId: bookId)

        XCTAssertEqual(annotations.bookId, bookId)
        XCTAssertTrue(annotations.highlights.isEmpty)
    }

    func testBookAnnotationsAddHighlight() {
        let bookId = UUID()
        var annotations = BookAnnotations(bookId: bookId)
        let originalUpdate = annotations.updatedAt

        Foundation.Thread.sleep(forTimeInterval: 0.01)

        let highlight = Highlight(chapterId: "ch1", selectedText: "Test", surroundingContext: "")
        annotations.addHighlight(highlight)

        XCTAssertEqual(annotations.highlights.count, 1)
        XCTAssertEqual(annotations.highlights[0].selectedText, "Test")
        XCTAssertGreaterThan(annotations.updatedAt, originalUpdate)
    }

    func testBookAnnotationsRemoveHighlight() {
        let bookId = UUID()
        var annotations = BookAnnotations(bookId: bookId)

        let h1 = Highlight(chapterId: "ch1", selectedText: "First", surroundingContext: "")
        let h2 = Highlight(chapterId: "ch1", selectedText: "Second", surroundingContext: "")
        annotations.addHighlight(h1)
        annotations.addHighlight(h2)

        XCTAssertEqual(annotations.highlights.count, 2)

        annotations.removeHighlight(id: h1.id)

        XCTAssertEqual(annotations.highlights.count, 1)
        XCTAssertEqual(annotations.highlights[0].id, h2.id)
    }

    func testBookAnnotationsRemoveNonexistentHighlight() {
        let bookId = UUID()
        var annotations = BookAnnotations(bookId: bookId)

        let highlight = Highlight(chapterId: "ch1", selectedText: "Test", surroundingContext: "")
        annotations.addHighlight(highlight)

        // Try to remove a non-existent highlight
        annotations.removeHighlight(id: UUID())

        XCTAssertEqual(annotations.highlights.count, 1)
    }

    func testBookAnnotationsAddThread() {
        let bookId = UUID()
        var annotations = BookAnnotations(bookId: bookId)

        let highlight = Highlight(chapterId: "ch1", selectedText: "Test", surroundingContext: "")
        annotations.addHighlight(highlight)

        var thread = AnnotationThread()
        thread.addMessage(ThreadMessage(role: .assistant, content: "Analysis"))

        annotations.addThread(to: highlight.id, thread: thread)

        XCTAssertEqual(annotations.highlights[0].threads.count, 1)
        XCTAssertEqual(annotations.highlights[0].threads[0].messages.count, 1)
    }

    func testBookAnnotationsAddThreadToNonexistentHighlight() {
        let bookId = UUID()
        var annotations = BookAnnotations(bookId: bookId)

        let thread = AnnotationThread()
        annotations.addThread(to: UUID(), thread: thread)

        // Should not crash, just do nothing
        XCTAssertTrue(annotations.highlights.isEmpty)
    }

    func testBookAnnotationsCodable() throws {
        let bookId = UUID()
        var annotations = BookAnnotations(bookId: bookId)

        let cfi = CFIRange(startPath: "/1", startOffset: 0, endPath: "/1", endOffset: 10)
        let highlight = Highlight(
            chapterId: "ch1",
            selectedText: "Selected text",
            surroundingContext: "Full context here",
            cfiRange: cfi
        )
        annotations.addHighlight(highlight)

        var thread = AnnotationThread()
        thread.addMessage(ThreadMessage(role: .user, content: "Question"))
        thread.addMessage(ThreadMessage(role: .assistant, content: "Answer"))
        annotations.addThread(to: highlight.id, thread: thread)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(annotations)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(BookAnnotations.self, from: data)

        XCTAssertEqual(decoded.bookId, bookId)
        XCTAssertEqual(decoded.highlights.count, 1)
        XCTAssertEqual(decoded.highlights[0].threads.count, 1)
        XCTAssertEqual(decoded.highlights[0].threads[0].messages.count, 2)
    }

    // MARK: - MarginNoteData Tests

    func testMarginNoteDataEquality() {
        let data1 = MarginNoteData(
            highlightId: "123",
            previewText: "Preview",
            isCommitted: true,
            hasThread: false,
            threadContent: nil,
            isLoading: false
        )

        let data2 = MarginNoteData(
            highlightId: "123",
            previewText: "Preview",
            isCommitted: true,
            hasThread: false,
            threadContent: nil,
            isLoading: false
        )

        let data3 = MarginNoteData(
            highlightId: "456",
            previewText: "Preview",
            isCommitted: true,
            hasThread: false,
            threadContent: nil,
            isLoading: false
        )

        XCTAssertEqual(data1, data2)
        XCTAssertNotEqual(data1, data3)
    }

    func testMarginNoteDataCodable() throws {
        let original = MarginNoteData(
            highlightId: "abc-123",
            previewText: "Test preview",
            isCommitted: true,
            hasThread: true,
            threadContent: "<div>Thread HTML</div>",
            isLoading: false
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MarginNoteData.self, from: data)

        XCTAssertEqual(original, decoded)
    }
}
