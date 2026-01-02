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
        let zipData = try Data(contentsOf: zipURL)
        try extractZipData(zipData, to: destination)
    }

    // MARK: - Pure Swift ZIP Extraction

    private func extractZipData(_ data: Data, to destination: URL) throws {
        var offset = 0

        while offset + 30 <= data.count {
            // Check for local file header signature: 0x04034b50 (little-endian: 50 4b 03 04)
            let sig = data.subdata(in: offset..<offset+4)
            guard sig == Data([0x50, 0x4b, 0x03, 0x04]) else {
                // Not a local file header - might be central directory or end of zip
                break
            }

            // Parse local file header
            let generalPurpose = readUInt16(data, at: offset + 6)
            let compressionMethod = readUInt16(data, at: offset + 8)
            let compressedSize = readUInt32(data, at: offset + 18)
            let uncompressedSize = readUInt32(data, at: offset + 22)
            let fileNameLength = Int(readUInt16(data, at: offset + 26))
            let extraFieldLength = Int(readUInt16(data, at: offset + 28))

            let fileNameStart = offset + 30
            let fileNameEnd = fileNameStart + fileNameLength

            guard fileNameEnd <= data.count else {
                throw EPUBParserError.invalidEPUB
            }

            let fileNameData = data.subdata(in: fileNameStart..<fileNameEnd)
            guard let fileName = String(data: fileNameData, encoding: .utf8) else {
                throw EPUBParserError.invalidEPUB
            }

            let dataStart = fileNameEnd + extraFieldLength

            // Handle data descriptor (bit 3 of general purpose flag)
            var actualCompressedSize = Int(compressedSize)
            var actualUncompressedSize = Int(uncompressedSize)

            if (generalPurpose & 0x08) != 0 && compressedSize == 0 {
                // Data descriptor follows - need to find it by scanning
                // For simplicity, we'll search for the next local file header or central directory
                if let nextHeader = findNextZipHeader(in: data, from: dataStart) {
                    actualCompressedSize = nextHeader - dataStart
                    // Check if there's a data descriptor (12 or 16 bytes before next header)
                    if nextHeader >= dataStart + 16 {
                        let potentialSig = data.subdata(in: (nextHeader - 16)..<(nextHeader - 12))
                        if potentialSig == Data([0x50, 0x4b, 0x07, 0x08]) {
                            actualCompressedSize = nextHeader - 16 - dataStart
                        }
                    }
                }
            }

            let dataEnd = dataStart + actualCompressedSize

            guard dataEnd <= data.count else {
                throw EPUBParserError.invalidEPUB
            }

            let compressedData = data.subdata(in: dataStart..<dataEnd)

            // Create file path
            let filePath = destination.appendingPathComponent(fileName)

            // Handle directories
            if fileName.hasSuffix("/") {
                try fileManager.createDirectory(at: filePath, withIntermediateDirectories: true)
            } else {
                // Ensure parent directory exists
                let parentDir = filePath.deletingLastPathComponent()
                try fileManager.createDirectory(at: parentDir, withIntermediateDirectories: true)

                // Decompress and write file
                let decompressedData: Data

                switch compressionMethod {
                case 0: // Stored (no compression)
                    decompressedData = compressedData
                case 8: // Deflate
                    decompressedData = try decompressDeflate(compressedData, expectedSize: actualUncompressedSize > 0 ? actualUncompressedSize : compressedData.count * 4)
                default:
                    throw EPUBParserError.parsingFailed("Unsupported compression method: \(compressionMethod)")
                }

                try decompressedData.write(to: filePath)
            }

            offset = dataEnd
        }
    }

    private func findNextZipHeader(in data: Data, from start: Int) -> Int? {
        var i = start
        while i + 4 <= data.count {
            let sig = data.subdata(in: i..<i+4)
            // Local file header or central directory header
            if sig == Data([0x50, 0x4b, 0x03, 0x04]) || sig == Data([0x50, 0x4b, 0x01, 0x02]) {
                return i
            }
            i += 1
        }
        return data.count
    }

    private func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
               (UInt32(data[offset + 1]) << 8) |
               (UInt32(data[offset + 2]) << 16) |
               (UInt32(data[offset + 3]) << 24)
    }

    private func decompressDeflate(_ data: Data, expectedSize: Int) throws -> Data {
        // Use raw DEFLATE (no zlib header) - ZIP uses raw deflate
        let bufferSize = max(expectedSize, 65536)
        var decompressed = Data(count: bufferSize)

        let result = data.withUnsafeBytes { sourcePtr -> Int in
            decompressed.withUnsafeMutableBytes { destPtr -> Int in
                guard let sourceBase = sourcePtr.baseAddress,
                      let destBase = destPtr.baseAddress else { return 0 }

                let decodedSize = compression_decode_buffer(
                    destBase.assumingMemoryBound(to: UInt8.self),
                    bufferSize,
                    sourceBase.assumingMemoryBound(to: UInt8.self),
                    data.count,
                    nil,
                    COMPRESSION_ZLIB  // Note: This handles raw deflate
                )
                return decodedSize
            }
        }

        guard result > 0 else {
            throw EPUBParserError.parsingFailed("Decompression failed")
        }

        decompressed.removeSubrange(result..<decompressed.count)
        return decompressed
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

        // Handle decimal numeric entities like &#8220;
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

        // Handle hexadecimal numeric entities like &#x201C;
        let hexPattern = #"&#[xX]([0-9a-fA-F]+);"#
        if let regex = try? NSRegularExpression(pattern: hexPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            for match in matches.reversed() {
                if let range = Range(match.range, in: result),
                   let hexRange = Range(match.range(at: 1), in: result),
                   let codePoint = Int(result[hexRange], radix: 16),
                   let scalar = Unicode.Scalar(codePoint) {
                    result.replaceSubrange(range, with: String(Character(scalar)))
                }
            }
        }

        return result
    }
}
