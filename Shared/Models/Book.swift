import Foundation

struct Book: Identifiable, Hashable {
    let id: UUID
    let fileURL: URL
    let title: String
    let author: String?
    let coverImage: Data?
    let chapters: [Chapter]
    let metadata: BookMetadata

    init(
        id: UUID = UUID(),
        fileURL: URL,
        title: String,
        author: String? = nil,
        coverImage: Data? = nil,
        chapters: [Chapter] = [],
        metadata: BookMetadata = BookMetadata()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.title = title
        self.author = author
        self.coverImage = coverImage
        self.chapters = chapters
        self.metadata = metadata
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Book, rhs: Book) -> Bool {
        lhs.id == rhs.id
    }
}

struct BookMetadata: Hashable {
    var language: String?
    var publisher: String?
    var publicationDate: Date?
    var description: String?
    var subjects: [String] = []
}
