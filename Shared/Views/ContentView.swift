import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StoredBook.lastOpenedAt, order: .reverse) private var storedBooks: [StoredBook]

    @State private var selectedBook: Book?
    @State private var error: Error?
    @State private var isLoading = false

    private let parser = EPUBParser()
    private let storage = BookStorage.shared

    var body: some View {
        @Bindable var appState = appState

        Group {
            if let book = selectedBook, let bookId = appState.selectedBookId {
                // Reader view when a book is open
                ReaderView(book: book, bookId: bookId)
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                appState.selectedBookId = nil
                                selectedBook = nil
                            } label: {
                                Label("Library", systemImage: "chevron.left")
                            }
                        }
                    }
            } else {
                // Library view as main scene
                LibraryMainView(
                    storedBooks: storedBooks,
                    onSelectBook: { bookId in
                        appState.selectedBookId = bookId
                    },
                    onAddBook: { openFile() },
                    onDeleteBook: { book in
                        deleteBook(book)
                    }
                )
            }
        }
        .onChange(of: appState.selectedBookId) { _, newId in
            if let newId {
                Task { await loadBook(id: newId) }
            } else {
                selectedBook = nil
            }
        }
        .onChange(of: appState.showOpenPanel) { _, show in
            if show {
                openFile()
                appState.showOpenPanel = false
            }
        }
        .alert("Error", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            if let error {
                Text(error.localizedDescription)
            }
        }
        .overlay {
            if isLoading {
                ProgressView("Loading...")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func deleteBook(_ book: StoredBook) {
        Task {
            try? await BookStorage.shared.removeBook(book.id)
        }
        if appState.selectedBookId == book.id {
            appState.selectedBookId = nil
        }
        modelContext.delete(book)
    }

    private func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.epub]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            Task { await importBook(from: url) }
        }
        #endif
    }

    private func importBook(from url: URL) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // Copy to app storage
            let (storedURL, bookId) = try await storage.importBook(from: url)

            // Parse the book
            let book = try await parser.parse(url: storedURL)

            // Create SwiftData record
            let storedBook = StoredBook(
                id: bookId,
                title: book.title,
                author: book.author,
                totalChapters: book.chapters.count
            )
            modelContext.insert(storedBook)
            try modelContext.save()

            // Select the new book
            appState.selectedBookId = bookId
        } catch {
            self.error = error
        }
    }

    private func loadBook(id: UUID) async {
        isLoading = true
        defer { isLoading = false }

        do {
            let url = await storage.bookURL(for: id)
            let book = try await parser.parse(url: url)

            // Update last opened time
            if let storedBook = storedBooks.first(where: { $0.id == id }) {
                storedBook.markOpened()
            }

            selectedBook = book
        } catch {
            self.error = error
        }
    }
}

#Preview {
    ContentView()
        .environment(AppState())
        .modelContainer(for: StoredBook.self, inMemory: true)
}
