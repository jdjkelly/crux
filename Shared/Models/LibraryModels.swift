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

    // Cached metadata
    var language: String?
    var publisher: String?
    var bookDescription: String?

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
    }

    var progress: Double {
        guard totalChapters > 0 else { return 0 }
        return Double(currentChapterIndex) / Double(totalChapters)
    }

    func markOpened() {
        lastOpenedAt = Date()
    }

    func updateProgress(chapter: Int, total: Int) {
        currentChapterIndex = chapter
        totalChapters = total
        if chapter >= total - 1 {
            isFinished = true
        }
    }
}
