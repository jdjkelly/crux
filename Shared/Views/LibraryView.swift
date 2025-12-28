import SwiftUI
import SwiftData

// MARK: - Main Library View (full screen)

struct LibraryMainView: View {
    let storedBooks: [StoredBook]
    let onSelectBook: (UUID) -> Void
    let onAddBook: () -> Void
    let onDeleteBook: (StoredBook) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if storedBooks.isEmpty {
                    EmptyLibraryView(onAddBook: onAddBook)
                } else {
                    BookListView(
                        books: storedBooks,
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
        }
    }
}

struct BookListView: View {
    let books: [StoredBook]
    let onSelectBook: (UUID) -> Void
    let onDeleteBook: (StoredBook) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(books) { book in
                    BookListRow(book: book)
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
                            .padding(.leading, 24)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .frame(maxWidth: 680)
        .frame(maxWidth: .infinity)
    }
}

struct BookListRow: View {
    let book: StoredBook
    @State private var isHovered = false

    private var progressFraction: Double? {
        guard book.totalChapters > 0 else { return nil }
        if book.isFinished { return 1.0 }
        return Double(book.currentChapterIndex) / Double(book.totalChapters)
    }

    private var progressText: String? {
        guard book.totalChapters > 0 else { return nil }
        if book.isFinished {
            return "Finished"
        } else if book.currentChapterIndex > 0 {
            return "\(book.currentChapterIndex + 1) of \(book.totalChapters)"
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Main content
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: 16, weight: .medium, design: .serif))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let author = book.author {
                    Text(author)
                        .font(.system(size: 14, design: .serif))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 16)

            // Progress indicator
            if let fraction = progressFraction {
                VStack(alignment: .trailing, spacing: 4) {
                    if let text = progressText {
                        Text(text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(book.isFinished ? Color.green : .secondary)
                    }

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))

                            Capsule()
                                .fill(book.isFinished ? Color.green : Color.primary.opacity(0.35))
                                .frame(width: geo.size.width * fraction)
                        }
                    }
                    .frame(width: 60, height: 3)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(isHovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
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
