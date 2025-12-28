import Foundation

/// Represents a CFI (Canonical Fragment Identifier) range within a chapter
/// CFI is the EPUB standard for referencing locations in content documents
struct CFIRange: Codable, Equatable {
    /// DOM path to start container (e.g., "/4/2/1")
    let startPath: String
    /// Character offset within start text node
    let startOffset: Int
    /// DOM path to end container
    let endPath: String
    /// Character offset within end text node
    let endOffset: Int

    /// Combined CFI string representation
    var cfiString: String {
        "\(startPath):\(startOffset),\(endPath):\(endOffset)"
    }
}

/// Data from a text selection in the WebView
struct SelectionData: Equatable {
    let text: String
    let cfiRange: CFIRange
    let context: String
}

/// Action from a margin note in the WebView
enum MarginNoteAction {
    case commitHighlight(highlightId: UUID)
    case startThread(highlightId: UUID)
    case sendFollowUp(highlightId: UUID, message: String)
    case deleteHighlight(highlightId: UUID)
}

/// Data to send to JavaScript for rendering margin notes
struct MarginNoteData: Codable, Equatable {
    let highlightId: String
    let previewText: String
    let isCommitted: Bool  // Whether the highlight is saved (shows Highlight button if false)
    let hasThread: Bool
    let threadContent: String?  // HTML for thread messages
    let isLoading: Bool
}

/// All annotations for a single book, stored as JSON
struct BookAnnotations: Codable {
    let bookId: UUID
    var highlights: [Highlight]
    var updatedAt: Date

    init(bookId: UUID, highlights: [Highlight] = []) {
        self.bookId = bookId
        self.highlights = highlights
        self.updatedAt = Date()
    }

    mutating func addHighlight(_ highlight: Highlight) {
        highlights.append(highlight)
        updatedAt = Date()
    }

    mutating func removeHighlight(id: UUID) {
        highlights.removeAll { $0.id == id }
        updatedAt = Date()
    }

    mutating func addThread(to highlightId: UUID, thread: Thread) {
        if let index = highlights.firstIndex(where: { $0.id == highlightId }) {
            highlights[index].threads.append(thread)
            updatedAt = Date()
        }
    }
}

/// A highlighted passage in a book
struct Highlight: Codable, Identifiable {
    let id: UUID
    let chapterId: String
    let selectedText: String
    let surroundingContext: String
    let cfiRange: CFIRange?  // Optional for backwards compatibility with existing highlights
    var threads: [Thread]
    let createdAt: Date

    init(
        id: UUID = UUID(),
        chapterId: String,
        selectedText: String,
        surroundingContext: String,
        cfiRange: CFIRange? = nil,
        threads: [Thread] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.chapterId = chapterId
        self.selectedText = selectedText
        self.surroundingContext = surroundingContext
        self.cfiRange = cfiRange
        self.threads = threads
        self.createdAt = createdAt
    }
}

/// An AI conversation thread attached to a highlight
struct Thread: Codable, Identifiable {
    let id: UUID
    var messages: [ThreadMessage]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        messages: [ThreadMessage] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    mutating func addMessage(_ message: ThreadMessage) {
        messages.append(message)
        updatedAt = Date()
    }
}

/// A single message in a thread (user prompt or AI response)
struct ThreadMessage: Codable, Identifiable {
    let id: UUID
    let role: MessageRole
    let content: String
    let createdAt: Date

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum MessageRole: String, Codable {
    case user
    case assistant
}
