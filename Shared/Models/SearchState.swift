import Foundation
import SwiftUI

/// Search scope options
enum SearchScope: String, CaseIterable {
    case chapter = "Chapter"
    case book = "Book"
}

/// A single search match (for book-wide search results)
struct SearchMatch: Identifiable, Hashable {
    let id = UUID()
    let text: String
    let chapterId: String
    let chapterTitle: String
    let chapterIndex: Int
    let matchIndex: Int
}

/// Observable search state for the reader
@Observable
class SearchState {
    var isSearchActive = false
    var query = ""
    var scope: SearchScope = .chapter

    // In-chapter results (from JavaScript)
    var inChapterMatchCount = 0
    var inChapterCurrentIndex = 0

    // Book-wide results
    var bookMatches: [SearchMatch] = []

    var hasMatches: Bool {
        switch scope {
        case .chapter:
            return inChapterMatchCount > 0
        case .book:
            return !bookMatches.isEmpty
        }
    }

    func reset() {
        query = ""
        inChapterMatchCount = 0
        inChapterCurrentIndex = 0
        bookMatches = []
    }
}
