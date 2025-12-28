import XCTest
@testable import Crux

final class EPUBParserTests: XCTestCase {

    // MARK: - Manifest Parsing Tests

    func testParseManifestWithIdBeforeHref() async throws {
        let opfContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <manifest>
                <item id="chapter1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
                <item id="chapter2" href="chapter2.xhtml" media-type="application/xhtml+xml"/>
            </manifest>
            <spine>
                <itemref idref="chapter1"/>
                <itemref idref="chapter2"/>
            </spine>
        </package>
        """

        let manifest = parseManifest(from: opfContent)

        XCTAssertEqual(manifest["chapter1"], "chapter1.xhtml")
        XCTAssertEqual(manifest["chapter2"], "chapter2.xhtml")
    }

    func testParseManifestWithHrefBeforeId() async throws {
        let opfContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
            <manifest>
                <item href="text/chapter1.xhtml" id="ch1" media-type="application/xhtml+xml"/>
                <item href="text/chapter2.xhtml" id="ch2" media-type="application/xhtml+xml"/>
            </manifest>
            <spine>
                <itemref idref="ch1"/>
                <itemref idref="ch2"/>
            </spine>
        </package>
        """

        let manifest = parseManifest(from: opfContent)

        XCTAssertEqual(manifest["ch1"], "text/chapter1.xhtml")
        XCTAssertEqual(manifest["ch2"], "text/chapter2.xhtml")
    }

    func testParseManifestWithMixedAttributeOrders() async throws {
        let opfContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package>
            <manifest>
                <item id="intro" href="intro.xhtml" media-type="application/xhtml+xml"/>
                <item media-type="application/xhtml+xml" href="chapter1.xhtml" id="ch1"/>
                <item href="chapter2.xhtml" media-type="application/xhtml+xml" id="ch2"/>
            </manifest>
            <spine>
                <itemref idref="intro"/>
                <itemref idref="ch1"/>
                <itemref idref="ch2"/>
            </spine>
        </package>
        """

        let manifest = parseManifest(from: opfContent)

        XCTAssertEqual(manifest.count, 3)
        XCTAssertEqual(manifest["intro"], "intro.xhtml")
        XCTAssertEqual(manifest["ch1"], "chapter1.xhtml")
        XCTAssertEqual(manifest["ch2"], "chapter2.xhtml")
    }

    func testParseManifestWithSelfClosingTags() async throws {
        let opfContent = """
        <manifest>
            <item id="ch1" href="ch1.xhtml" />
            <item id="ch2" href="ch2.xhtml"/>
        </manifest>
        """

        let manifest = parseManifest(from: opfContent)

        XCTAssertEqual(manifest["ch1"], "ch1.xhtml")
        XCTAssertEqual(manifest["ch2"], "ch2.xhtml")
    }

    // MARK: - Spine Parsing Tests

    func testParseSpineOrder() async throws {
        let opfContent = """
        <spine>
            <itemref idref="cover"/>
            <itemref idref="toc"/>
            <itemref idref="chapter1"/>
            <itemref idref="chapter2"/>
        </spine>
        """

        let spineIds = parseSpine(from: opfContent)

        XCTAssertEqual(spineIds, ["cover", "toc", "chapter1", "chapter2"])
    }

    // MARK: - Container Parsing Tests

    func testParseContainerXml() throws {
        let containerXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles>
                <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """

        let opfPath = parseContainer(from: containerXml)

        XCTAssertEqual(opfPath, "OEBPS/content.opf")
    }

    func testParseContainerXmlWithDifferentPath() throws {
        let containerXml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0">
            <rootfiles>
                <rootfile full-path="content/book.opf" media-type="application/oebps-package+xml"/>
            </rootfiles>
        </container>
        """

        let opfPath = parseContainer(from: containerXml)

        XCTAssertEqual(opfPath, "content/book.opf")
    }

    // MARK: - Metadata Extraction Tests

    func testExtractTitle() {
        let content = """
        <metadata>
            <dc:title>The Great Gatsby</dc:title>
            <dc:creator>F. Scott Fitzgerald</dc:creator>
        </metadata>
        """

        let title = extractMetadata(from: content, tag: "dc:title")

        XCTAssertEqual(title, "The Great Gatsby")
    }

    func testExtractAuthor() {
        let content = """
        <metadata>
            <dc:title>1984</dc:title>
            <dc:creator>George Orwell</dc:creator>
        </metadata>
        """

        let author = extractMetadata(from: content, tag: "dc:creator")

        XCTAssertEqual(author, "George Orwell")
    }

    func testExtractMissingMetadata() {
        let content = """
        <metadata>
            <dc:title>Some Book</dc:title>
        </metadata>
        """

        let author = extractMetadata(from: content, tag: "dc:creator")

        XCTAssertNil(author)
    }

    // MARK: - Chapter Title Extraction Tests

    func testExtractChapterTitleFromH1() {
        let html = """
        <html>
        <body>
            <h1>Chapter One: The Beginning</h1>
            <p>It was a dark and stormy night...</p>
        </body>
        </html>
        """

        let title = extractChapterTitle(from: html)

        XCTAssertEqual(title, "Chapter One: The Beginning")
    }

    func testExtractChapterTitleFromH2WhenNoH1() {
        let html = """
        <html>
        <body>
            <h2>Introduction</h2>
            <p>Welcome to this book...</p>
        </body>
        </html>
        """

        let title = extractChapterTitle(from: html)

        XCTAssertEqual(title, "Introduction")
    }

    func testExtractChapterTitleFromTitleTag() {
        let html = """
        <html>
        <head>
            <title>Prologue</title>
        </head>
        <body>
            <p>Before our story begins...</p>
        </body>
        </html>
        """

        let title = extractChapterTitle(from: html)

        XCTAssertEqual(title, "Prologue")
    }

    // MARK: - Helper Methods (copied from EPUBParser for testing)

    private func parseManifest(from content: String) -> [String: String] {
        var manifest: [String: String] = [:]
        let itemPattern = #"<item\s+([^>]+)/?\s*>"#
        if let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: .caseInsensitive) {
            let matches = itemRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let attrsRange = Range(match.range(at: 1), in: content) {
                    let attrs = String(content[attrsRange])

                    let idPattern = #"id="([^"]+)""#
                    let hrefPattern = #"href="([^"]+)""#

                    var itemId: String?
                    var itemHref: String?

                    if let idRegex = try? NSRegularExpression(pattern: idPattern),
                       let idMatch = idRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                       let idRange = Range(idMatch.range(at: 1), in: attrs) {
                        itemId = String(attrs[idRange])
                    }

                    if let hrefRegex = try? NSRegularExpression(pattern: hrefPattern),
                       let hrefMatch = hrefRegex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
                       let hrefRange = Range(hrefMatch.range(at: 1), in: attrs) {
                        itemHref = String(attrs[hrefRange])
                    }

                    if let id = itemId, let href = itemHref {
                        manifest[id] = href
                    }
                }
            }
        }
        return manifest
    }

    private func parseSpine(from content: String) -> [String] {
        var spineIds: [String] = []
        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for match in matches {
                if let idRange = Range(match.range(at: 1), in: content) {
                    spineIds.append(String(content[idRange]))
                }
            }
        }
        return spineIds
    }

    private func parseContainer(from content: String) -> String? {
        let pattern = #"full-path="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[range])
    }

    private func extractMetadata(from content: String, tag: String) -> String? {
        let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return nil
        }
        return String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractChapterTitle(from html: String) -> String? {
        for tag in ["h1", "h2", "title"] {
            let pattern = "<\(tag)[^>]*>([^<]+)</\(tag)>"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(match.range(at: 1), in: html) {
                let title = String(html[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    return title
                }
            }
        }
        return nil
    }
}
