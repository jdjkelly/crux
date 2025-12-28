import SwiftUI
import MarkdownUI

@MainActor
@Observable
final class ThreadPanelState {
    var isLoading = false
    var currentHighlight: Highlight?
    var currentThread: Thread?
    var error: Error?

    private let claudeService = ClaudeService()
    private let storage = BookStorage.shared

    var isConfigured: Bool {
        get async {
            await claudeService.isConfigured
        }
    }

    func startThread(
        for highlight: Highlight,
        book: Book,
        chapter: Chapter?,
        bookId: UUID
    ) async -> Thread? {
        isLoading = true
        error = nil

        // Create a new thread
        var thread = Thread()

        // Add initial assistant message (the explication)
        let context = ExplicationContext(
            bookTitle: book.title,
            author: book.author,
            chapterTitle: chapter?.title ?? "Unknown Chapter",
            surroundingText: highlight.surroundingContext
        )

        do {
            let response = try await claudeService.explicate(
                selectedText: highlight.selectedText,
                context: context
            )

            thread.addMessage(ThreadMessage(role: .assistant, content: response))
            currentThread = thread
            isLoading = false
            return thread
        } catch {
            self.error = error
            isLoading = false
            return nil
        }
    }

    func continueThread(
        message: String,
        highlight: Highlight,
        book: Book,
        existingThread: Thread? = nil
    ) async -> Thread? {
        // Use provided thread, fall back to currentThread, or get from highlight
        guard var thread = existingThread ?? currentThread ?? highlight.threads.first else { return nil }

        isLoading = true
        error = nil

        // Add user message
        thread.addMessage(ThreadMessage(role: .user, content: message))

        // Build conversation for Claude
        let prompt = """
        Continuing our discussion about this passage from "\(book.title)":

        "\(highlight.selectedText)"

        Previous context: \(thread.messages.dropLast().map { "\($0.role): \($0.content)" }.joined(separator: "\n\n"))

        User's follow-up: \(message)
        """

        do {
            let response = try await claudeService.explicate(
                selectedText: prompt,
                context: ExplicationContext(
                    bookTitle: book.title,
                    author: book.author,
                    chapterTitle: "",
                    surroundingText: ""
                )
            )

            thread.addMessage(ThreadMessage(role: .assistant, content: response))
            currentThread = thread
            isLoading = false
            return thread
        } catch {
            self.error = error
            isLoading = false
            return nil
        }
    }

    func setAPIKey(_ key: String) async {
        await claudeService.setAPIKey(key)
    }
}

struct ThreadPanel: View {
    let pendingSelection: SelectionData?
    let book: Book
    let chapter: Chapter?
    @Bindable var state: ThreadPanelState
    @Binding var annotations: BookAnnotations
    let onDismiss: () -> Void

    @State private var showingAPIKeyPrompt = false
    @State private var apiKey = ""
    @State private var followUpText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("AI Thread", systemImage: "bubble.left.and.bubble.right")
                    .font(.headline)
                Spacer()
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.bar)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let selection = pendingSelection {
                        // Selected text
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected Passage")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(selection.text)
                                .font(.body)
                                .padding()
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        // Start thread button or loading state
                        if state.isLoading && state.currentThread == nil {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Analyzing passage...")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        } else if state.currentThread == nil {
                            Button {
                                Task {
                                    let isConfigured = await state.isConfigured
                                    if isConfigured {
                                        await startNewThread(for: selection)
                                    } else {
                                        showingAPIKeyPrompt = true
                                    }
                                }
                            } label: {
                                Label("Start Thread", systemImage: "sparkles")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    // Thread messages
                    if let thread = state.currentThread {
                        ForEach(thread.messages) { message in
                            ThreadMessageView(message: message)
                        }

                        // Follow-up input
                        if !state.isLoading {
                            HStack {
                                TextField("Ask a follow-up...", text: $followUpText)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit {
                                        sendFollowUp()
                                    }

                                Button {
                                    sendFollowUp()
                                } label: {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.title2)
                                }
                                .disabled(followUpText.isEmpty)
                            }
                        } else {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Thinking...")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    // Error display
                    if let error = state.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Error", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)

                            Text(error.localizedDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if error.localizedDescription.contains("API key") {
                                Button("Configure API Key") {
                                    showingAPIKeyPrompt = true
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding()
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Existing highlights for this chapter
                    let chapterHighlights = annotations.highlights.filter { $0.chapterId == chapter?.id }
                    if !chapterHighlights.isEmpty && pendingSelection == nil {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Highlights in this chapter")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ForEach(chapterHighlights) { highlight in
                                HighlightRow(highlight: highlight)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(.background)
        .sheet(isPresented: $showingAPIKeyPrompt) {
            APIKeyPromptView(apiKey: $apiKey) { key in
                Task {
                    await state.setAPIKey(key)
                    if let selection = pendingSelection {
                        await startNewThread(for: selection)
                    }
                }
            }
        }
    }

    private func startNewThread(for selection: SelectionData) async {
        // Create or find highlight
        var highlight: Highlight
        if let existing = annotations.highlights.first(where: { $0.selectedText == selection.text && $0.cfiRange == selection.cfiRange }) {
            highlight = existing
        } else {
            highlight = Highlight(
                chapterId: chapter?.id ?? "",
                selectedText: selection.text,
                surroundingContext: selection.context,
                cfiRange: selection.cfiRange
            )
            annotations.addHighlight(highlight)
        }

        state.currentHighlight = highlight

        if let thread = await state.startThread(for: highlight, book: book, chapter: chapter, bookId: annotations.bookId) {
            // Save thread to annotations
            annotations.addThread(to: highlight.id, thread: thread)
            await saveAnnotations()
        }
    }

    private func sendFollowUp() {
        guard !followUpText.isEmpty, let highlight = state.currentHighlight else { return }
        let message = followUpText
        followUpText = ""
        Task {
            if let thread = await state.continueThread(message: message, highlight: highlight, book: book) {
                // Update thread in annotations
                if let highlightIndex = annotations.highlights.firstIndex(where: { $0.id == highlight.id }),
                   let threadIndex = annotations.highlights[highlightIndex].threads.firstIndex(where: { $0.id == thread.id }) {
                    annotations.highlights[highlightIndex].threads[threadIndex] = thread
                    await saveAnnotations()
                }
            }
        }
    }

    private func saveAnnotations() async {
        do {
            try await BookStorage.shared.saveAnnotations(annotations)
        } catch {
            state.error = error
        }
    }

    private func extractSurroundingText(for selectedText: String) -> String {
        guard let content = chapter?.content else { return "" }
        let stripped = content.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)

        if let range = stripped.range(of: selectedText) {
            let contextLength = 500
            let start = stripped.index(range.lowerBound, offsetBy: -contextLength, limitedBy: stripped.startIndex) ?? stripped.startIndex
            let end = stripped.index(range.upperBound, offsetBy: contextLength, limitedBy: stripped.endIndex) ?? stripped.endIndex
            return String(stripped[start..<end])
        }

        return String(stripped.prefix(1000))
    }
}

struct ThreadMessageView: View {
    let message: ThreadMessage

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
            Text(message.role == .user ? "You" : "Claude")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Markdown(message.content)
                .textSelection(.enabled)
                .padding(12)
                .background(message.role == .user ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
}

struct HighlightRow: View {
    let highlight: Highlight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(highlight.selectedText)
                .font(.caption)
                .lineLimit(2)

            if !highlight.threads.isEmpty {
                Text("\(highlight.threads.count) thread\(highlight.threads.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct APIKeyPromptView: View {
    @Binding var apiKey: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("API Key", text: $apiKey)
                } header: {
                    Text("Claude API Key")
                } footer: {
                    Text("Get your API key from console.anthropic.com")
                }
            }
            .navigationTitle("Configure API")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(apiKey)
                        dismiss()
                    }
                    .disabled(apiKey.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(width: 400, height: 200)
        #endif
    }
}
