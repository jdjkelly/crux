import Foundation

/// Utility for extracting plain text from HTML content for search
enum HTMLTextExtractor {

    /// Strip HTML tags and return plain text for searching
    static func extractText(from html: String) -> String {
        var text = html

        // Remove script/style content entirely
        text = text.replacingOccurrences(
            of: "<(script|style)[^>]*>[\\s\\S]*?</\\1>",
            with: "",
            options: .regularExpression
        )

        // Replace block elements with newlines
        text = text.replacingOccurrences(
            of: "</(p|div|h[1-6]|li|br|tr)[^>]*>",
            with: "\n",
            options: .regularExpression
        )

        // Remove remaining tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: "",
            options: .regularExpression
        )

        // Decode common HTML entities
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")

        // Normalize whitespace
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Find all matches in text, returning context snippets
    static func findMatches(
        in text: String,
        query: String,
        contextLength: Int = 50
    ) -> [(range: Range<String.Index>, snippet: String)] {
        guard !query.isEmpty else { return [] }

        var results: [(Range<String.Index>, String)] = []
        let lowercaseText = text.lowercased()
        let lowercaseQuery = query.lowercased()
        var searchStart = text.startIndex

        while searchStart < text.endIndex,
              let range = lowercaseText.range(
                  of: lowercaseQuery,
                  range: searchStart..<text.endIndex
              ) {
            // Convert range from lowercased text to original text
            let lowerDistance = lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound)
            let upperDistance = lowercaseText.distance(from: lowercaseText.startIndex, to: range.upperBound)

            let originalLower = text.index(text.startIndex, offsetBy: lowerDistance)
            let originalUpper = text.index(text.startIndex, offsetBy: upperDistance)
            let originalRange = originalLower..<originalUpper

            // Extract context snippet
            let contextStart = text.index(
                originalLower,
                offsetBy: -contextLength,
                limitedBy: text.startIndex
            ) ?? text.startIndex
            let contextEnd = text.index(
                originalUpper,
                offsetBy: contextLength,
                limitedBy: text.endIndex
            ) ?? text.endIndex

            var snippet = String(text[contextStart..<contextEnd])

            // Add ellipsis if truncated
            if contextStart != text.startIndex {
                snippet = "..." + snippet
            }
            if contextEnd != text.endIndex {
                snippet = snippet + "..."
            }

            results.append((originalRange, snippet))
            searchStart = range.upperBound
        }

        return results
    }
}
