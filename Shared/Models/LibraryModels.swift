import Foundation
import SwiftData

@Model
final class StoredBook {
    @Attribute(.unique) var id: UUID
    var title: String
    var author: String?
    var addedAt: Date
    var lastOpenedAt: Date?

    // Reading progress
    var currentChapterIndex: Int
    var totalChapters: Int
    var isFinished: Bool
    var scrollPosition: Double = 0  // 0.0-1.0 percentage within chapter

    // Cached metadata
    var language: String?
    var publisher: String?
    var bookDescription: String?
    var publicationYear: Int?
    var subjectsJSON: String?  // JSON-encoded [String] array

    var subjects: [String] {
        guard let json = subjectsJSON,
              let data = json.data(using: .utf8),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    init(
        id: UUID,
        title: String,
        author: String? = nil,
        addedAt: Date = Date(),
        currentChapterIndex: Int = 0,
        totalChapters: Int = 0
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.addedAt = addedAt
        self.lastOpenedAt = nil
        self.currentChapterIndex = currentChapterIndex
        self.totalChapters = totalChapters
        self.isFinished = false
        self.scrollPosition = 0
    }

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(currentChapterIndex) / Double(totalChapters)
    }

    func markOpened() {
        lastOpenedAt = Date()
    }

    func updateProgress(chapter: Int, total: Int, scroll: Double = 0) {
        currentChapterIndex = chapter
        totalChapters = total
        scrollPosition = scroll
        if chapter >= total - 1 && scroll > 0.9 {
            isFinished = true
        }
    }
}
