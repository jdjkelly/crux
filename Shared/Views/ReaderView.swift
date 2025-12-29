import SwiftUI
import SwiftData
import WebKit

struct ReaderView: View {
    let book: Book
    let bookId: UUID

    @Environment(\.modelContext) private var modelContext
    @Query private var storedBooks: [StoredBook]

    @State private var currentChapterIndex = 0
    @State private var threadState = ThreadPanelState()
    @State private var annotations = BookAnnotations(bookId: UUID())
    @State private var showingAPIKeyPrompt = false
    @State private var apiKey = ""
    @State private var loadingHighlightId: UUID? = nil
    @State private var pendingSelection: SelectionData? = nil
    @State private var pendingHighlightId: UUID? = nil

    private var storedBook: StoredBook? {
        storedBooks.first { $0.id == bookId }
    }

    var currentChapter: Chapter? {
        guard currentChapterIndex < book.chapters.count else { return nil }
        return book.chapters[currentChapterIndex]
    }

    var currentChapterHighlights: [Highlight] {
        guard let chapter = currentChapter else { return [] }
        return annotations.highlights.filter { $0.chapterId == chapter.id }
    }

    /// Highlights to display in WebView (includes pending uncommitted selection)
    var displayHighlights: [Highlight] {
        var highlights = currentChapterHighlights

        // Add pending selection as a temporary highlight
        if let pending = pendingSelection, let pendingId = pendingHighlightId, let chapter = currentChapter {
            let pendingHighlight = Highlight(
                id: pendingId,
                chapterId: chapter.id,
                selectedText: pending.text,
                surroundingContext: pending.context,
                cfiRange: pending.cfiRange
            )
            highlights.append(pendingHighlight)
        }

        return highlights
    }

    /// Convert markdown text to HTML
    private func markdownToHTML(_ text: String) -> String {
        var result = text

        // Escape HTML entities first
        result = result
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        // Bold: **text** or __text__
        if let regex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*|__(.+?)__"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<strong>$1$2</strong>")
        }

        // Italic: *text* or _text_ (but not inside words for underscore)
        if let regex = try? NSRegularExpression(pattern: #"\*([^*]+?)\*|(?<!\w)_([^_]+?)_(?!\w)"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<em>$1$2</em>")
        }

        // Inline code: `code`
        if let regex = try? NSRegularExpression(pattern: #"`([^`]+?)`"#) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "<code>$1</code>")
        }

        // Line breaks
        result = result.replacingOccurrences(of: "\n", with: "<br>")

        return result
    }

    /// Build margin note data from current highlights for passing to WebView
    var currentMarginNotes: [MarginNoteData] {
        var notes: [MarginNoteData] = []

        // Add pending selection first (if any) - uncommitted
        if let pending = pendingSelection, let pendingId = pendingHighlightId {
            notes.append(MarginNoteData(
                highlightId: pendingId.uuidString,
                previewText: String(pending.text.prefix(100)),
                isCommitted: false,
                hasThread: false,
                threadContent: nil,
                isLoading: false
            ))
        }

        // Add committed highlights for current chapter
        for highlight in currentChapterHighlights {
            let thread = highlight.threads.first
            let isLoading = loadingHighlightId == highlight.id

            // Build thread content HTML if there are messages
            var threadContent: String? = nil
            if let thread = thread, !thread.messages.isEmpty {
                threadContent = thread.messages.map { msg in
                    let roleClass = msg.role == .user ? "user" : "assistant"
                    let htmlContent = markdownToHTML(msg.content)
                    return "<div class=\"thread-message \(roleClass)\">\(htmlContent)</div>"
                }.joined()
            }

            notes.append(MarginNoteData(
                highlightId: highlight.id.uuidString,
                previewText: String(highlight.selectedText.prefix(100)),
                isCommitted: true,
                hasThread: thread != nil,
                threadContent: threadContent,
                isLoading: isLoading
            ))
        }

        return notes
    }

    var body: some View {
        VStack(spacing: 0) {
            if let chapter = currentChapter {
                EPUBWebView(
                    chapter: chapter,
                    highlights: displayHighlights,
                    marginNotes: currentMarginNotes,
                    onTextSelected: { selectionData in
                        handleTextSelection(selectionData)
                    },
                    onHighlightTapped: { _ in
                        // Handled by margin notes in WebView
                    },
                    onMarginNoteAction: { action in
                        handleMarginNoteAction(action)
                    }
                )
            } else {
                Text("No content available")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Navigation bar
            HStack {
                Button {
                    navigateToChapter(currentChapterIndex - 1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentChapterIndex == 0)

                Spacer()

                if let chapter = currentChapter {
                    Text(chapter.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    navigateToChapter(currentChapterIndex + 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentChapterIndex >= book.chapters.count - 1)
            }
            .padding()
            .background(.bar)
        }
        .navigationTitle(book.title)
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(Array(book.chapters.enumerated()), id: \.offset) { index, chapter in
                        Button {
                            navigateToChapter(index)
                        } label: {
                            HStack {
                                Text(String(repeating: "    ", count: chapter.depth) + chapter.title)
                                    .font(chapter.depth == 0 ? .body.weight(.medium) : .body)
                            }
                        }
                    }
                } label: {
                    Label("Chapters", systemImage: "list.bullet")
                }
            }
        }
        .task {
            await loadState()
        }
        #if os(macOS)
        .onKeyPress(.leftArrow) {
            if currentChapterIndex > 0 {
                navigateToChapter(currentChapterIndex - 1)
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.rightArrow) {
            if currentChapterIndex < book.chapters.count - 1 {
                navigateToChapter(currentChapterIndex + 1)
                return .handled
            }
            return .ignored
        }
        #endif
        .sheet(isPresented: $showingAPIKeyPrompt) {
            APIKeyPromptView(apiKey: $apiKey) { key in
                Task {
                    await threadState.setAPIKey(key)
                }
            }
        }
    }

    private func handleTextSelection(_ selectionData: SelectionData) {
        guard currentChapter != nil else { return }

        // Check if this highlight already exists (committed)
        if annotations.highlights.contains(where: { $0.selectedText == selectionData.text && $0.cfiRange == selectionData.cfiRange }) {
            return
        }

        // Store as pending (don't save yet - wait for user to click Highlight or Annotate)
        pendingSelection = selectionData
        pendingHighlightId = UUID()
    }

    private func clearPendingSelection() {
        pendingSelection = nil
        pendingHighlightId = nil
    }

    private func commitPendingHighlight() -> Highlight? {
        guard let pending = pendingSelection,
              let pendingId = pendingHighlightId,
              let chapter = currentChapter else { return nil }

        let highlight = Highlight(
            id: pendingId,
            chapterId: chapter.id,
            selectedText: pending.text,
            surroundingContext: pending.context,
            cfiRange: pending.cfiRange
        )
        annotations.addHighlight(highlight)
        clearPendingSelection()
        return highlight
    }

    private func handleMarginNoteAction(_ action: MarginNoteAction) {
        Task {
            switch action {
            case .commitHighlight(let highlightId):
                // Commit pending selection if it matches
                if pendingHighlightId == highlightId {
                    if let _ = commitPendingHighlight() {
                        try? await BookStorage.shared.saveAnnotations(annotations)
                    }
                }

            case .startThread(let highlightId):
                let isConfigured = await threadState.isConfigured
                guard isConfigured else {
                    showingAPIKeyPrompt = true
                    return
                }

                // If this is a pending selection, commit it first
                var highlight: Highlight?
                if pendingHighlightId == highlightId {
                    highlight = commitPendingHighlight()
                    if highlight != nil {
                        try? await BookStorage.shared.saveAnnotations(annotations)
                    }
                } else {
                    highlight = annotations.highlights.first(where: { $0.id == highlightId })
                }

                guard let highlight = highlight else { return }

                // Set loading state - triggers margin note update
                loadingHighlightId = highlightId

                if let thread = await threadState.startThread(
                    for: highlight,
                    book: book,
                    chapter: currentChapter,
                    bookId: annotations.bookId
                ) {
                    annotations.addThread(to: highlightId, thread: thread)
                    try? await BookStorage.shared.saveAnnotations(annotations)
                }

                // Clear loading state - triggers margin note update with content
                loadingHighlightId = nil

            case .sendFollowUp(let highlightId, let message):
                let isConfigured = await threadState.isConfigured
                guard isConfigured else {
                    showingAPIKeyPrompt = true
                    return
                }

                guard let highlight = annotations.highlights.first(where: { $0.id == highlightId }) else { return }

                // Set loading state
                loadingHighlightId = highlightId

                // Get the existing thread from the highlight
                let existingThread = highlight.threads.first

                if let thread = await threadState.continueThread(
                    message: message,
                    highlight: highlight,
                    book: book,
                    existingThread: existingThread
                ) {
                    // Update the thread in annotations
                    if let highlightIndex = annotations.highlights.firstIndex(where: { $0.id == highlightId }),
                       let threadIndex = annotations.highlights[highlightIndex].threads.firstIndex(where: { $0.id == thread.id }) {
                        annotations.highlights[highlightIndex].threads[threadIndex] = thread
                        try? await BookStorage.shared.saveAnnotations(annotations)
                    }
                }

                // Clear loading state
                loadingHighlightId = nil

            case .deleteHighlight(let highlightId):
                // If deleting a pending selection, just clear it
                if pendingHighlightId == highlightId {
                    clearPendingSelection()
                } else {
                    annotations.removeHighlight(id: highlightId)
                    try? await BookStorage.shared.saveAnnotations(annotations)
                }
            }
        }
    }

    private func navigateToChapter(_ index: Int) {
        guard index >= 0 && index < book.chapters.count else { return }
        clearPendingSelection()  // Discard uncommitted selection on chapter change
        currentChapterIndex = index
        saveProgress()
    }

    private func saveProgress() {
        storedBook?.updateProgress(chapter: currentChapterIndex, total: book.chapters.count)
    }

    private func loadState() async {
        // Load saved chapter position
        if let stored = storedBook {
            currentChapterIndex = min(stored.currentChapterIndex, book.chapters.count - 1)
        }

        // Load annotations
        do {
            annotations = try await BookStorage.shared.loadAnnotations(for: bookId)
        } catch {
            annotations = BookAnnotations(bookId: bookId)
        }
    }
}

// WebView for rendering EPUB HTML content
struct EPUBWebView: View {
    let chapter: Chapter
    let highlights: [Highlight]
    let marginNotes: [MarginNoteData]
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    var onMarginNoteAction: ((MarginNoteAction) -> Void)? = nil

    var body: some View {
        EPUBWebViewRepresentable(
            html: chapter.content,
            highlights: highlights,
            marginNotes: marginNotes,
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction
        )
    }
}
