import SwiftUI
import SwiftData

// MARK: - Main Library View (full screen)

struct LibraryMainView: View {
    let storedBooks: [StoredBook]
    let onSelectBook: (UUID) -> Void
    let onAddBook: () -> Void
    let onDeleteBook: (StoredBook) -> Void

    @State private var searchQuery = ""
    @State private var annotationStats: [UUID: AnnotationStats] = [:]

    private var filteredBooks: [StoredBook] {
        guard !searchQuery.isEmpty else { return storedBooks }
        let query = searchQuery.lowercased()
        return storedBooks.filter { book in
            book.title.lowercased().contains(query) ||
            (book.author?.lowercased().contains(query) ?? false) ||
            book.subjects.contains { $0.lowercased().contains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search bar
                if !storedBooks.isEmpty {
                    LibrarySearchBar(query: $searchQuery)
                }

                // Content
                if storedBooks.isEmpty {
                    EmptyLibraryView(onAddBook: onAddBook)
                } else if filteredBooks.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
                    BookListView(
                        books: filteredBooks,
                        annotationStats: annotationStats,
                        onSelectBook: onSelectBook,
                        onDeleteBook: onDeleteBook
                    )
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: onAddBook) {
                        Label("Add Book", systemImage: "plus")
                    }
                }
            }
            .task {
                await loadAnnotationStats()
            }
            .onChange(of: storedBooks.count) { _, _ in
                Task { await loadAnnotationStats() }
            }
        }
    }

    private func loadAnnotationStats() async {
        for book in storedBooks {
            let stats = await BookStorage.shared.loadAnnotationStats(for: book.id)
            annotationStats[book.id] = stats
        }
    }
}

struct LibrarySearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search library...", text: $query)
                .textFieldStyle(.plain)

            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary)
        .cornerRadius(8)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

struct BookListView: View {
    let books: [StoredBook]
    let annotationStats: [UUID: AnnotationStats]
    let onSelectBook: (UUID) -> Void
    let onDeleteBook: (StoredBook) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    BookListRow(
                        book: book,
                        stats: annotationStats[book.id]
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelectBook(book.id)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            onDeleteBook(book)
                        } label: {
                            Label("Remove from Library", systemImage: "trash")
                        }
                    }

                    if book.id != books.last?.id {
                        Divider()
                            .padding(.leading, 16)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: 720)
        .frame(maxWidth: .infinity)
    }
}

struct BookListRow: View {
    let book: StoredBook
    let stats: AnnotationStats?
    @State private var isHovered = false

    private var progressFraction: Double {
        guard book.totalChapters > 0 else { return 0 }
        if book.isFinished { return 1.0 }
        return Double(book.currentChapterIndex) / Double(book.totalChapters)
    }

    private var progressPercent: Int {
        Int(progressFraction * 100)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // Line 1: Title + Added date
            HStack(alignment: .top) {
                Text(book.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text("Added \(book.addedAt.relativeShort)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            // Line 2: Author · Publisher · Year · Language
            MetadataLine(book: book)

            // Line 3: Progress bar + Chapter position + Last read
            ProgressLine(book: book, progressFraction: progressFraction, progressPercent: progressPercent)

            // Line 4: Annotations + Subjects
            AnnotationLine(stats: stats, subjects: book.subjects)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Row Components

struct MetadataLine: View {
    let book: StoredBook

    var body: some View {
        HStack(spacing: 0) {
            let parts = metadataParts
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Text(part)
                if index < parts.count - 1 {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var metadataParts: [String] {
        var parts: [String] = []
        if let author = book.author, !author.isEmpty {
            parts.append(author)
        }
        if let publisher = book.publisher, !publisher.isEmpty {
            parts.append(publisher)
        }
        if let year = book.publicationYear {
            parts.append(String(year))
        }
        if let language = book.language, !language.isEmpty {
            parts.append(language.uppercased())
        }
        return parts
    }
}

struct ProgressLine: View {
    let book: StoredBook
    let progressFraction: Double
    let progressPercent: Int

    var body: some View {
        HStack(spacing: 8) {
            // Progress bar (flex width)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(book.isFinished ? Color.green : Color.primary.opacity(0.4))
                        .frame(width: max(0, geo.size.width * progressFraction))
                }
            }
            .frame(height: 4)

            // Chapter progress
            if book.totalChapters > 0 {
                Text(chapterText)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(book.isFinished ? .green : .secondary)
            }

            // Last read
            if let lastOpened = book.lastOpenedAt {
                Text("·")
                    .foregroundStyle(.quaternary)
                Text("Read \(lastOpened.relativeShort)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var chapterText: String {
        if book.isFinished {
            return "Done"
        }
        return "Ch \(book.currentChapterIndex + 1)/\(book.totalChapters) (\(progressPercent)%)"
    }
}

struct AnnotationLine: View {
    let stats: AnnotationStats?
    let subjects: [String]

    var body: some View {
        HStack(spacing: 0) {
            // Annotation stats
            if let stats = stats, stats.highlightCount > 0 || stats.threadCount > 0 {
                HStack(spacing: 8) {
                    if stats.highlightCount > 0 {
                        Label("\(stats.highlightCount)", systemImage: "highlighter")
                            .font(.system(size: 11))
                    }
                    if stats.threadCount > 0 {
                        Label("\(stats.threadCount)", systemImage: "bubble.left")
                            .font(.system(size: 11))
                    }
                }
                .foregroundStyle(.tertiary)

                if !subjects.isEmpty {
                    Text(" · ")
                        .foregroundStyle(.quaternary)
                }
            }

            // Subjects
            if !subjects.isEmpty {
                Text(subjects.prefix(3).joined(separator: ", "))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }
}

struct EmptyLibraryView: View {
    let onAddBook: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text("Your library is empty")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(.primary)

                Text("Add an EPUB to start reading")
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(.secondary)
            }

            Button(action: onAddBook) {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add Book")
                        .font(.system(size: 14, weight: .medium))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.primary.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LibraryMainView(
        storedBooks: [],
        onSelectBook: { _ in },
        onAddBook: {},
        onDeleteBook: { _ in }
    )
    .modelContainer(for: StoredBook.self, inMemory: true)
}
