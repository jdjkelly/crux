import XCTest
@testable import Crux

final class HTMLTextExtractorTests: XCTestCase {

    // MARK: - Text Extraction Tests

    func testExtractTextFromSimpleHTML() {
        let html = "<p>Hello, world!</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertEqual(result, "Hello, world!")
    }

    func testExtractTextPreservesPlainText() {
        let text = "Plain text without HTML"
        let result = HTMLTextExtractor.extractText(from: text)
        XCTAssertEqual(result, text)
    }

    func testExtractTextRemovesMultipleTags() {
        let html = "<div><h1>Title</h1><p>Paragraph one.</p><p>Paragraph two.</p></div>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertTrue(result.contains("Title"))
        XCTAssertTrue(result.contains("Paragraph one."))
        XCTAssertTrue(result.contains("Paragraph two."))
    }

    func testExtractTextRemovesScriptTags() {
        let html = "<p>Before</p><script>alert('xss');</script><p>After</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertFalse(result.contains("alert"))
        XCTAssertFalse(result.contains("xss"))
        XCTAssertTrue(result.contains("Before"))
        XCTAssertTrue(result.contains("After"))
    }

    func testExtractTextRemovesStyleTags() {
        let html = "<style>.red { color: red; }</style><p>Styled text</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertFalse(result.contains("color"))
        XCTAssertFalse(result.contains(".red"))
        XCTAssertTrue(result.contains("Styled text"))
    }

    func testExtractTextDecodesHTMLEntities() {
        let html = "<p>Tom &amp; Jerry &lt;3 &quot;cheese&quot;</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertTrue(result.contains("Tom & Jerry"))
        XCTAssertTrue(result.contains("<3"))
        XCTAssertTrue(result.contains("\"cheese\""))
    }

    func testExtractTextDecodesNbsp() {
        let html = "<p>Word&nbsp;with&nbsp;spaces</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertTrue(result.contains("Word with spaces"))
    }

    func testExtractTextDecodesApostrophe() {
        let html = "<p>It&#39;s working</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertTrue(result.contains("It's working"))
    }

    func testExtractTextNormalizesWhitespace() {
        let html = "<p>Multiple    spaces   and\n\nnewlines</p>"
        let result = HTMLTextExtractor.extractText(from: html)
        // Should be normalized to single spaces
        XCTAssertFalse(result.contains("  "))
    }

    func testExtractTextTrimsWhitespace() {
        let html = "   <p>Content</p>   "
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertEqual(result, "Content")
    }

    func testExtractTextHandlesNestedTags() {
        let html = "<div><span><strong>Bold</strong> and <em>italic</em></span></div>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertTrue(result.contains("Bold"))
        XCTAssertTrue(result.contains("italic"))
    }

    func testExtractTextHandlesEmptyHTML() {
        let html = ""
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertEqual(result, "")
    }

    func testExtractTextHandlesTagsOnly() {
        let html = "<div><span></span></div>"
        let result = HTMLTextExtractor.extractText(from: html)
        XCTAssertEqual(result, "")
    }

    // MARK: - Search Match Tests

    func testFindMatchesBasicSearch() {
        let text = "The quick brown fox jumps over the lazy dog."
        let matches = HTMLTextExtractor.findMatches(in: text, query: "fox")

        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].snippet.contains("fox"))
    }

    func testFindMatchesCaseInsensitive() {
        let text = "Hello World"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "world")

        XCTAssertEqual(matches.count, 1)
    }

    func testFindMatchesMultipleOccurrences() {
        let text = "The cat sat on the mat. The cat was fat."
        let matches = HTMLTextExtractor.findMatches(in: text, query: "cat")

        XCTAssertEqual(matches.count, 2)
    }

    func testFindMatchesNoMatch() {
        let text = "Hello World"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "xyz")

        XCTAssertEqual(matches.count, 0)
    }

    func testFindMatchesEmptyQuery() {
        let text = "Hello World"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "")

        XCTAssertEqual(matches.count, 0)
    }

    func testFindMatchesSnippetContext() {
        let text = "This is a long text with the word target somewhere in the middle of it."
        let matches = HTMLTextExtractor.findMatches(in: text, query: "target", contextLength: 10)

        XCTAssertEqual(matches.count, 1)
        XCTAssertTrue(matches[0].snippet.contains("target"))
        XCTAssertTrue(matches[0].snippet.contains("...")) // Should have ellipsis
    }

    func testFindMatchesAtStart() {
        let text = "Start of the text"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "Start", contextLength: 5)

        XCTAssertEqual(matches.count, 1)
        // Should NOT have leading ellipsis since match is at start
        XCTAssertFalse(matches[0].snippet.hasPrefix("..."))
    }

    func testFindMatchesAtEnd() {
        let text = "Text at the end"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "end", contextLength: 5)

        XCTAssertEqual(matches.count, 1)
        // Should NOT have trailing ellipsis since match is at end
        XCTAssertFalse(matches[0].snippet.hasSuffix("..."))
    }

    func testFindMatchesRangeIsCorrect() {
        let text = "Find the word here"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "word")

        XCTAssertEqual(matches.count, 1)
        let matchedText = String(text[matches[0].range])
        XCTAssertEqual(matchedText, "word")
    }

    func testFindMatchesPreservesOriginalCase() {
        let text = "Find the Word here"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "word")

        XCTAssertEqual(matches.count, 1)
        let matchedText = String(text[matches[0].range])
        XCTAssertEqual(matchedText, "Word") // Original case preserved
    }

    func testFindMatchesOverlappingNotPossible() {
        // "aa" in "aaa" should find 1 match (non-overlapping)
        let text = "aaa"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "aa")

        // Should find only one (starts at 0, next search starts at 2)
        XCTAssertEqual(matches.count, 1)
    }

    func testFindMatchesUnicode() {
        let text = "Cafe with cafe and Cafe"
        let matches = HTMLTextExtractor.findMatches(in: text, query: "cafe")

        XCTAssertEqual(matches.count, 3)
    }

    // MARK: - Integration Tests

    func testExtractAndSearch() {
        let html = """
        <html>
        <head><style>.highlight { color: yellow; }</style></head>
        <body>
        <h1>Chapter One</h1>
        <p>It was the best of times, it was the worst of times.</p>
        <script>console.log('hidden');</script>
        </body>
        </html>
        """

        let text = HTMLTextExtractor.extractText(from: html)
        let matches = HTMLTextExtractor.findMatches(in: text, query: "times")

        XCTAssertFalse(text.contains("style"))
        XCTAssertFalse(text.contains("script"))
        XCTAssertFalse(text.contains("console"))
        XCTAssertEqual(matches.count, 2) // "times" appears twice
    }
}
