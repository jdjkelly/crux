import Foundation

actor BookStorage {
    static let shared = BookStorage()

    private let fileManager = FileManager.default
    private let booksDirectory: URL
    private let annotationsDirectory: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        booksDirectory = docs.appendingPathComponent("Books", isDirectory: true)
        annotationsDirectory = docs.appendingPathComponent("Annotations", isDirectory: true)

        // Ensure directories exist
        try? FileManager.default.createDirectory(at: booksDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: annotationsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Book Storage

    /// Copies an EPUB file into the app's managed storage
    /// Returns the new URL and a generated UUID for the book
    func importBook(from sourceURL: URL) throws -> (storedURL: URL, bookId: UUID) {
        let bookId = UUID()
        let destinationURL = booksDirectory.appendingPathComponent("\(bookId.uuidString).epub")

        // Start accessing security-scoped resource if needed
        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return (destinationURL, bookId)
    }

    /// Returns the stored URL for a book by ID
    func bookURL(for bookId: UUID) -> URL {
        booksDirectory.appendingPathComponent("\(bookId.uuidString).epub")
    }

    /// Checks if a book exists in storage
    func bookExists(_ bookId: UUID) -> Bool {
        fileManager.fileExists(atPath: bookURL(for: bookId).path)
    }

    /// Removes a book from storage
    func removeBook(_ bookId: UUID) throws {
        let url = bookURL(for: bookId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        // Also remove annotations
        try? removeAnnotations(for: bookId)
    }

    /// Lists all stored book IDs
    func listStoredBookIds() throws -> [UUID] {
        let contents = try fileManager.contentsOfDirectory(at: booksDirectory, includingPropertiesForKeys: nil)
        return contents.compactMap { url -> UUID? in
            guard url.pathExtension == "epub" else { return nil }
            return UUID(uuidString: url.deletingPathExtension().lastPathComponent)
        }
    }

    // MARK: - Annotations Storage

    func annotationsURL(for bookId: UUID) -> URL {
        annotationsDirectory.appendingPathComponent("\(bookId.uuidString).json")
    }

    func loadAnnotations(for bookId: UUID) throws -> BookAnnotations {
        let url = annotationsURL(for: bookId)
        guard fileManager.fileExists(atPath: url.path) else {
            return BookAnnotations(bookId: bookId)
        }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(BookAnnotations.self, from: data)
    }

    func saveAnnotations(_ annotations: BookAnnotations) throws {
        let url = annotationsURL(for: annotations.bookId)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(annotations)
        try data.write(to: url, options: .atomic)
    }

    func removeAnnotations(for bookId: UUID) throws {
        let url = annotationsURL(for: bookId)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - Annotation Stats

    func loadAnnotationStats(for bookId: UUID) -> AnnotationStats {
        let url = annotationsURL(for: bookId)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return AnnotationStats(highlightCount: 0, threadCount: 0)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let annotations = try? decoder.decode(BookAnnotations.self, from: data) else {
            return AnnotationStats(highlightCount: 0, threadCount: 0)
        }

        let highlightCount = annotations.highlights.count
        let threadCount = annotations.highlights.reduce(0) { $0 + $1.threads.count }

        return AnnotationStats(highlightCount: highlightCount, threadCount: threadCount)
    }
}

struct AnnotationStats {
    let highlightCount: Int
    let threadCount: Int
}
