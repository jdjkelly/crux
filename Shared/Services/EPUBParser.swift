import Foundation
import Compression

enum EPUBParserError: Error, LocalizedError {
    case invalidEPUB
    case missingContainer
    case missingOPF
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidEPUB:
            return "The file is not a valid EPUB"
        case .missingContainer:
            return "Missing container.xml in EPUB"
        case .missingOPF:
            return "Missing OPF file in EPUB"
        case .parsingFailed(let message):
            return "Parsing failed: \(message)"
        }
    }
}

actor EPUBParser {
    private let fileManager = FileManager.default

    func parse(url: URL) async throws -> Book {
        // Create temp directory for extraction
        let tempDir = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)

        defer {
            try? fileManager.removeItem(at: tempDir)
        }

        // Extract EPUB (it's a ZIP file)
        try await extractZip(from: url, to: tempDir)

        // Parse container.xml to find OPF location
        let containerPath = tempDir.appendingPathComponent("META-INF/container.xml")
        guard fileManager.fileExists(atPath: containerPath.path) else {
            throw EPUBParserError.missingContainer
        }

        let containerData = try Data(contentsOf: containerPath)
        let opfPath = try parseContainer(containerData)

        // Parse OPF file
        let opfURL = tempDir.appendingPathComponent(opfPath)
        let opfData = try Data(contentsOf: opfURL)
        let opfDirectory = opfURL.deletingLastPathComponent()

        return try parseOPF(opfData, baseURL: opfDirectory, fileURL: url)
    }

    private func extractZip(from zipURL: URL, to destination: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destination.path]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw EPUBParserError.invalidEPUB
        }
    }

    private func parseContainer(_ data: Data) throws -> String {
        guard let content = String(data: data, encoding: .utf8) else {
            throw EPUBParserError.parsingFailed("Cannot read container.xml")
        }

        // Simple regex to extract rootfile path
        let pattern = #"full-path="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            throw EPUBParserError.missingOPF
        }

        return String(content[range])
    }

    private func parseOPF(_ data: Data, baseURL: URL, fileURL: URL) throws -> Book {
        guard let content = String(data: data, encoding: .utf8) else {
            throw EPUBParserError.parsingFailed("Cannot read OPF file")
        }

        // Extract metadata
        let title = extractMetadata(from: content, tag: "dc:title") ?? "Unknown Title"
        let author = extractMetadata(from: content, tag: "dc:creator")
        let language = extractMetadata(from: content, tag: "dc:language")
        let publisher = extractMetadata(from: content, tag: "dc:publisher")
        let description = extractMetadata(from: content, tag: "dc:description")

        // Build manifest (id -> href mapping)
        let manifest = parseManifest(content)

        // Try to parse TOC from NCX (EPUB 2) or nav.xhtml (EPUB 3)
        var chapters = try parseTOC(content, manifest: manifest, baseURL: baseURL)

        // If no TOC found, fall back to spine-based chapters
        if chapters.isEmpty {
            chapters = try parseSpineFallback(content, manifest: manifest, baseURL: baseURL)
        }

        // Try to find cover image
        let coverImage = try? findCoverImage(content, baseURL: baseURL)

        return Book(
            fileURL: fileURL,
            title: title,
            author: author,
            coverImage: coverImage,
            chapters: chapters,
            metadata: BookMetadata(
                language: language,
                publisher: publisher,
                description: description
            )
        )
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

    private func parseManifest(_ content: String) -> [String: String] {
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

    // MARK: - TOC Parsing

    private func parseTOC(_ opfContent: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        // First try EPUB 3 nav document
        if let navChapters = try? parseEPUB3Nav(opfContent, manifest: manifest, baseURL: baseURL), !navChapters.isEmpty {
            return navChapters
        }

        // Fall back to EPUB 2 NCX
        if let ncxChapters = try? parseNCX(opfContent, manifest: manifest, baseURL: baseURL), !ncxChapters.isEmpty {
            return ncxChapters
        }

        return []
    }

    // MARK: - EPUB 3 Navigation Document

    private func parseEPUB3Nav(_ opfContent: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        // Find nav document in manifest (has properties="nav")
        let navPattern = #"<item[^>]+properties="[^"]*nav[^"]*"[^>]+href="([^"]+)""#
        let navPatternAlt = #"<item[^>]+href="([^"]+)"[^>]+properties="[^"]*nav[^"]*""#

        var navHref: String?

        for pattern in [navPattern, navPatternAlt] {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: opfContent, range: NSRange(opfContent.startIndex..., in: opfContent)),
               let range = Range(match.range(at: 1), in: opfContent) {
                navHref = String(opfContent[range])
                break
            }
        }

        guard let href = navHref else { return [] }

        let navURL = baseURL.appendingPathComponent(href)
        let navDirectory = navURL.deletingLastPathComponent()
        guard let navContent = try? String(contentsOf: navURL, encoding: .utf8) else { return [] }

        return parseNavDocument(navContent, baseURL: navDirectory)
    }

    private func parseNavDocument(_ content: String, baseURL: URL) -> [Chapter] {
        var chapters: [Chapter] = []
        var order = 0

        // Find the toc nav element
        let tocPattern = #"<nav[^>]+epub:type="toc"[^>]*>([\s\S]*?)</nav>"#
        guard let regex = try? NSRegularExpression(pattern: tocPattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
              let range = Range(match.range(at: 1), in: content) else {
            return []
        }

        let tocContent = String(content[range])
        parseNavList(tocContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: 0)

        return chapters
    }

    private func parseNavList(_ content: String, baseURL: URL, chapters: inout [Chapter], order: inout Int, depth: Int) {
        // Parse <li> elements with <a> tags
        let liPattern = #"<li[^>]*>([\s\S]*?)</li>"#

        guard let liRegex = try? NSRegularExpression(pattern: liPattern, options: .caseInsensitive) else { return }

        let matches = liRegex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        for match in matches {
            guard let range = Range(match.range(at: 1), in: content) else { continue }
            let liContent = String(content[range])

            // Extract the anchor
            let aPattern = #"<a[^>]+href="([^"]+)"[^>]*>([^<]+)</a>"#
            if let aRegex = try? NSRegularExpression(pattern: aPattern, options: .caseInsensitive),
               let aMatch = aRegex.firstMatch(in: liContent, range: NSRange(liContent.startIndex..., in: liContent)),
               let hrefRange = Range(aMatch.range(at: 1), in: liContent),
               let textRange = Range(aMatch.range(at: 2), in: liContent) {

                let href = decodeHTMLEntities(String(liContent[hrefRange]))
                let title = decodeHTMLEntities(String(liContent[textRange])).trimmingCharacters(in: .whitespacesAndNewlines)

                if !title.isEmpty {
                    let chapterURL = baseURL.appendingPathComponent(href.removingPercentEncoding ?? href)
                    let filePath = href.components(separatedBy: "#").first ?? href
                    let contentURL = baseURL.appendingPathComponent(filePath.removingPercentEncoding ?? filePath)
                    let contentString = (try? String(contentsOf: contentURL, encoding: .utf8)) ?? ""

                    chapters.append(Chapter(
                        id: "nav-\(order)",
                        title: title,
                        href: href,
                        content: contentString,
                        order: order,
                        depth: depth
                    ))
                    order += 1
                }
            }

            // Check for nested <ol> (sub-items)
            let nestedOlPattern = #"<ol[^>]*>([\s\S]*?)</ol>"#
            if let olRegex = try? NSRegularExpression(pattern: nestedOlPattern, options: .caseInsensitive),
               let olMatch = olRegex.firstMatch(in: liContent, range: NSRange(liContent.startIndex..., in: liContent)),
               let olRange = Range(olMatch.range(at: 1), in: liContent) {
                let nestedContent = String(liContent[olRange])
                parseNavList(nestedContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: depth + 1)
            }
        }
    }

    // MARK: - EPUB 2 NCX Parsing

    private func parseNCX(_ opfContent: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        // Find NCX file in manifest (media-type="application/x-dtbncx+xml")
        var ncxHref: String?

        for (_, href) in manifest {
            if href.lowercased().hasSuffix(".ncx") {
                ncxHref = href
                break
            }
        }

        // Also check for explicit NCX reference in spine
        let spinePattern = #"<spine[^>]+toc="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: spinePattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: opfContent, range: NSRange(opfContent.startIndex..., in: opfContent)),
           let range = Range(match.range(at: 1), in: opfContent) {
            let tocId = String(opfContent[range])
            if let href = manifest[tocId] {
                ncxHref = href
            }
        }

        guard let href = ncxHref else { return [] }

        let ncxURL = baseURL.appendingPathComponent(href)
        let ncxDirectory = ncxURL.deletingLastPathComponent()
        guard let ncxContent = try? String(contentsOf: ncxURL, encoding: .utf8) else { return [] }

        return parseNCXContent(ncxContent, baseURL: ncxDirectory)
    }

    private func parseNCXContent(_ content: String, baseURL: URL) -> [Chapter] {
        var chapters: [Chapter] = []
        var order = 0

        // Find navMap - use greedy match since there's only one navMap
        guard let navMapStart = content.range(of: "<navMap", options: .caseInsensitive),
              let navMapEnd = content.range(of: "</navMap>", options: .caseInsensitive) else {
            return []
        }

        let navMapContent = String(content[navMapStart.upperBound..<navMapEnd.lowerBound])

        // Find top-level navPoints and process them recursively
        parseNavPointsAtLevel(navMapContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: 0)

        return chapters
    }

    /// Parse navPoints at a given level, handling nesting recursively
    private func parseNavPointsAtLevel(_ content: String, baseURL: URL, chapters: inout [Chapter], order: inout Int, depth: Int) {
        var searchStart = content.startIndex

        while let openRange = content.range(of: "<navPoint", options: .caseInsensitive, range: searchStart..<content.endIndex) {
            // Find the matching </navPoint> tag, accounting for nesting
            guard let navPointEnd = findMatchingCloseTag(in: content, tagName: "navPoint", from: openRange.lowerBound) else {
                break
            }

            let navPointContent = String(content[openRange.lowerBound..<navPointEnd])
            processNavPointRecursive(navPointContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: depth)

            searchStart = navPointEnd
        }
    }

    /// Find the matching close tag for a given open tag, handling nesting
    private func findMatchingCloseTag(in content: String, tagName: String, from startIndex: String.Index) -> String.Index? {
        let openTag = "<\(tagName)"
        let closeTag = "</\(tagName)>"

        var nestLevel = 0
        var currentIndex = startIndex

        while currentIndex < content.endIndex {
            let remaining = content[currentIndex...]

            if remaining.hasPrefix(openTag) {
                nestLevel += 1
                currentIndex = content.index(currentIndex, offsetBy: openTag.count, limitedBy: content.endIndex) ?? content.endIndex
            } else if remaining.hasPrefix(closeTag) {
                nestLevel -= 1
                if nestLevel == 0 {
                    return content.index(currentIndex, offsetBy: closeTag.count, limitedBy: content.endIndex)
                }
                currentIndex = content.index(currentIndex, offsetBy: closeTag.count, limitedBy: content.endIndex) ?? content.endIndex
            } else {
                currentIndex = content.index(after: currentIndex)
            }
        }

        return nil
    }

    /// Process a single navPoint and its children recursively
    private func processNavPointRecursive(_ content: String, baseURL: URL, chapters: inout [Chapter], order: inout Int, depth: Int) {
        // Extract navLabel text
        var title = ""
        if let labelStart = content.range(of: "<navLabel", options: .caseInsensitive),
           let textStart = content.range(of: "<text", options: .caseInsensitive, range: labelStart.upperBound..<content.endIndex),
           let textContentStart = content.range(of: ">", range: textStart.upperBound..<content.endIndex),
           let textEnd = content.range(of: "</text>", options: .caseInsensitive, range: textContentStart.upperBound..<content.endIndex) {
            title = decodeHTMLEntities(String(content[textContentStart.upperBound..<textEnd.lowerBound]))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Extract navPoint id attribute
        var navPointId = "ncx-\(order)"
        if let idAttr = content.range(of: "id=\"", options: .caseInsensitive),
           let idEnd = content.range(of: "\"", range: idAttr.upperBound..<content.endIndex) {
            navPointId = String(content[idAttr.upperBound..<idEnd.lowerBound])
        }

        // Extract content src
        var href = ""
        if let contentTag = content.range(of: "<content", options: .caseInsensitive),
           let srcAttr = content.range(of: "src=\"", options: .caseInsensitive, range: contentTag.upperBound..<content.endIndex),
           let srcEnd = content.range(of: "\"", range: srcAttr.upperBound..<content.endIndex) {
            href = decodeHTMLEntities(String(content[srcAttr.upperBound..<srcEnd.lowerBound]))
        }

        // Add this navPoint as a chapter
        if !title.isEmpty && !href.isEmpty {
            let filePath = href.components(separatedBy: "#").first ?? href
            let contentURL = baseURL.appendingPathComponent(filePath.removingPercentEncoding ?? filePath)
            let contentString = (try? String(contentsOf: contentURL, encoding: .utf8)) ?? ""

            chapters.append(Chapter(
                id: navPointId,
                title: title,
                href: href,
                content: contentString,
                order: order,
                depth: depth
            ))
            order += 1
        }

        // Find nested navPoints (children of this navPoint)
        // They appear after the </content> tag but before the final </navPoint>
        if let contentTagStart = content.range(of: "<content", options: .caseInsensitive),
           let contentTagEnd = content.range(of: "/>", range: contentTagStart.upperBound..<content.endIndex) {
            // Get content after the <content .../> tag
            let afterContent = String(content[contentTagEnd.upperBound...])

            // Remove the final </navPoint> and process nested navPoints
            let options: String.CompareOptions = [.caseInsensitive, .backwards]
            if let lastClose = afterContent.range(of: "</navPoint>", options: options) {
                let nestedContent = String(afterContent[..<lastClose.lowerBound])
                if nestedContent.contains("<navPoint") {
                    parseNavPointsAtLevel(nestedContent, baseURL: baseURL, chapters: &chapters, order: &order, depth: depth + 1)
                }
            }
        }
    }

    // MARK: - Fallback: Spine-based chapters

    private func parseSpineFallback(_ content: String, manifest: [String: String], baseURL: URL) throws -> [Chapter] {
        var chapters: [Chapter] = []

        let spinePattern = #"<itemref[^>]+idref="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: spinePattern) {
            let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))
            for (index, match) in matches.enumerated() {
                if let idRange = Range(match.range(at: 1), in: content) {
                    let idref = String(content[idRange])
                    if let href = manifest[idref] {
                        let chapterURL = baseURL.appendingPathComponent(href)
                        let chapterContent = (try? String(contentsOf: chapterURL, encoding: .utf8)) ?? ""
                        let title = extractChapterTitle(from: chapterContent) ?? "Chapter \(index + 1)"

                        chapters.append(Chapter(
                            id: idref,
                            title: title,
                            href: href,
                            content: chapterContent,
                            order: index,
                            depth: 0
                        ))
                    }
                }
            }
        }

        return chapters
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

    // MARK: - Cover Image

    private func findCoverImage(_ content: String, baseURL: URL) throws -> Data? {
        let coverPattern = #"<item[^>]+id="cover[^"]*"[^>]+href="([^"]+)""#
        if let regex = try? NSRegularExpression(pattern: coverPattern, options: .caseInsensitive),
           let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            let href = String(content[range])
            let coverURL = baseURL.appendingPathComponent(href)
            return try? Data(contentsOf: coverURL)
        }
        return nil
    }

    // MARK: - Utilities

    private func decodeHTMLEntities(_ string: String) -> String {
        var result = string
        let entities = [
            "&amp;": "&",
            "&lt;": "<",
            "&gt;": ">",
            "&quot;": "\"",
            "&apos;": "'",
            "&#39;": "'",
            "&nbsp;": " ",
            "&#160;": " ",
            "&ndash;": "–",
            "&mdash;": "—",
            "&hellip;": "…",
            "&rsquo;": "'",
            "&lsquo;": "'",
            "&rdquo;": "\u{201D}",
            "&ldquo;": "\u{201C}"
        ]

        for (entity, replacement) in entities {
            result = result.replacingOccurrences(of: entity, with: replacement)
        }

        // Handle numeric entities like &#8220;
        let numericPattern = #"&#(\d+);"#
        if let regex = try? NSRegularExpression(pattern: numericPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let numRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[numRange]),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
