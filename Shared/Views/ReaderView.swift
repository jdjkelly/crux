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
        currentChapterHighlights.map { highlight in
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

            return MarginNoteData(
                highlightId: highlight.id.uuidString,
                previewText: String(highlight.selectedText.prefix(100)),
                hasThread: thread != nil,
                threadContent: threadContent,
                isLoading: isLoading
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let chapter = currentChapter {
                EPUBWebView(
                    chapter: chapter,
                    highlights: currentChapterHighlights,
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
        // Create highlight immediately when text is selected
        guard let chapter = currentChapter else { return }

        // Check if this highlight already exists
        if annotations.highlights.contains(where: { $0.selectedText == selectionData.text && $0.cfiRange == selectionData.cfiRange }) {
            return
        }

        // Create new highlight
        let highlight = Highlight(
            chapterId: chapter.id,
            selectedText: selectionData.text,
            surroundingContext: selectionData.context,
            cfiRange: selectionData.cfiRange
        )
        annotations.addHighlight(highlight)

        // Save annotations
        Task {
            try? await BookStorage.shared.saveAnnotations(annotations)
        }
    }

    private func handleMarginNoteAction(_ action: MarginNoteAction) {
        Task {
            let isConfigured = await threadState.isConfigured
            guard isConfigured else {
                showingAPIKeyPrompt = true
                return
            }

            switch action {
            case .startThread(let highlightId):
                guard let highlight = annotations.highlights.first(where: { $0.id == highlightId }) else { return }

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
                annotations.removeHighlight(id: highlightId)
                try? await BookStorage.shared.saveAnnotations(annotations)
            }
        }
    }

    private func navigateToChapter(_ index: Int) {
        guard index >= 0 && index < book.chapters.count else { return }
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
        WebViewRepresentable(
            html: chapter.content,
            highlights: highlights,
            marginNotes: marginNotes,
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction
        )
    }
}

#if os(macOS)
struct WebViewRepresentable: NSViewRepresentable {
    let html: String
    let highlights: [Highlight]
    let marginNotes: [MarginNoteData]
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    let onMarginNoteAction: ((MarginNoteAction) -> Void)?

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelection")
        config.userContentController.add(context.coordinator, name: "highlightTapped")
        config.userContentController.add(context.coordinator, name: "marginNoteAction")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Inject all scripts
        let script = cfiScript() + "\n\n" + highlighterScript() + "\n\n" + selectionScript() + "\n\n" + marginNotesScript()
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        // Load initial content
        let styledHTML = wrapWithStyles(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
        context.coordinator.lastLoadedHTML = html
        context.coordinator.pendingHighlights = highlights
        context.coordinator.webView = webView

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if the HTML content actually changed
        if context.coordinator.lastLoadedHTML != html {
            let styledHTML = wrapWithStyles(html)
            webView.loadHTMLString(styledHTML, baseURL: nil)
            context.coordinator.lastLoadedHTML = html
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            context.coordinator.highlightsApplied = []
        } else if Set(context.coordinator.highlightsApplied) != Set(highlights.compactMap { $0.cfiRange != nil ? $0.id : nil }) {
            // Highlights changed but HTML didn't - apply new highlights
            // Also update pendingHighlights in case the page is still loading
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            context.coordinator.applyHighlights(highlights, to: webView)
        }

        // Update margin notes if they changed
        if context.coordinator.lastMarginNotes != marginNotes {
            context.coordinator.updateMarginNotes(marginNotes)
            context.coordinator.lastMarginNotes = marginNotes
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction
        )
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTextSelected: (SelectionData) -> Void
        let onHighlightTapped: (UUID) -> Void
        let onMarginNoteAction: ((MarginNoteAction) -> Void)?
        var lastLoadedHTML: String = ""
        var pendingHighlights: [Highlight] = []
        var pendingMarginNotes: [MarginNoteData] = []
        var highlightsApplied: [UUID] = []
        var lastMarginNotes: [MarginNoteData] = []
        weak var webView: WKWebView?

        init(
            onTextSelected: @escaping (SelectionData) -> Void,
            onHighlightTapped: @escaping (UUID) -> Void,
            onMarginNoteAction: ((MarginNoteAction) -> Void)?
        ) {
            self.onTextSelected = onTextSelected
            self.onHighlightTapped = onHighlightTapped
            self.onMarginNoteAction = onMarginNoteAction
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Apply highlights and margin notes after page loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.applyHighlights(self.pendingHighlights, to: webView)
                // Apply pending margin notes after highlights
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateMarginNotes(self.pendingMarginNotes)
                }
            }
        }

        func applyHighlights(_ highlights: [Highlight], to webView: WKWebView) {
            let highlightsWithCFI = highlights.compactMap { h -> [String: Any]? in
                guard let cfi = h.cfiRange else { return nil }
                return [
                    "id": h.id.uuidString,
                    "startPath": cfi.startPath,
                    "startOffset": cfi.startOffset,
                    "endPath": cfi.endPath,
                    "endOffset": cfi.endOffset
                ]
            }

            guard !highlightsWithCFI.isEmpty,
                  let jsonData = try? JSONSerialization.data(withJSONObject: highlightsWithCFI),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let js = "CruxHighlighter.applyHighlights(\(jsonString));"
            webView.evaluateJavaScript(js) { [weak self] _, error in
                if error == nil {
                    self?.highlightsApplied = highlightsWithCFI.compactMap { UUID(uuidString: $0["id"] as? String ?? "") }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "textSelection", let body = message.body as? [String: Any] {
                guard let text = body["text"] as? String, !text.isEmpty,
                      let startPath = body["startPath"] as? String,
                      let startOffset = body["startOffset"] as? Int,
                      let endPath = body["endPath"] as? String,
                      let endOffset = body["endOffset"] as? Int else { return }

                let context = body["context"] as? String ?? ""
                let cfiRange = CFIRange(
                    startPath: startPath,
                    startOffset: startOffset,
                    endPath: endPath,
                    endOffset: endOffset
                )
                let selectionData = SelectionData(text: text, cfiRange: cfiRange, context: context)

                DispatchQueue.main.async {
                    self.onTextSelected(selectionData)
                }
            } else if message.name == "highlightTapped", let idString = message.body as? String {
                if let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        self.onHighlightTapped(uuid)
                    }
                }
            } else if message.name == "marginNoteAction", let body = message.body as? [String: Any] {
                guard let action = body["action"] as? String,
                      let idString = body["highlightId"] as? String,
                      let highlightId = UUID(uuidString: idString) else { return }

                let noteAction: MarginNoteAction
                switch action {
                case "startThread":
                    noteAction = .startThread(highlightId: highlightId)
                case "sendFollowUp":
                    let message = body["message"] as? String ?? ""
                    noteAction = .sendFollowUp(highlightId: highlightId, message: message)
                case "deleteHighlight":
                    noteAction = .deleteHighlight(highlightId: highlightId)
                default:
                    return
                }

                DispatchQueue.main.async {
                    self.onMarginNoteAction?(noteAction)
                }
            }
        }

        /// Updates margin notes in the WebView with thread content
        func updateMarginNotes(_ notes: [MarginNoteData]) {
            guard let webView = webView,
                  let jsonData = try? JSONEncoder().encode(notes),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let js = "CruxMarginNotes.updateNotes(\(jsonString));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - JavaScript

    private func cfiScript() -> String {
        """
        const CruxCFI = {
            getPathToNode: function(node) {
                const path = [];
                let current = node;
                while (current && current !== document.body && current.parentNode) {
                    const parent = current.parentNode;
                    const children = Array.from(parent.childNodes).filter(c =>
                        c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
                    );
                    let position = 0;
                    for (let i = 0; i < children.length; i++) {
                        position++;
                        if (children[i] === current) break;
                    }
                    path.unshift(position);
                    current = parent;
                }
                return '/' + path.join('/');
            },

            getSelectionCFI: function() {
                const selection = window.getSelection();
                if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;

                const range = selection.getRangeAt(0);
                const text = selection.toString().trim();
                if (!text) return null;

                let startNode = range.startContainer;
                let endNode = range.endContainer;

                if (startNode.nodeType !== Node.TEXT_NODE) {
                    startNode = this.getFirstTextNode(startNode);
                }
                if (endNode.nodeType !== Node.TEXT_NODE) {
                    endNode = this.getLastTextNode(endNode);
                }
                if (!startNode || !endNode) return null;

                const context = this.getSurroundingContext(range, 500);

                return {
                    startPath: this.getPathToNode(startNode),
                    startOffset: range.startOffset,
                    endPath: this.getPathToNode(endNode),
                    endOffset: range.endOffset,
                    text: text,
                    context: context
                };
            },

            getFirstTextNode: function(node) {
                if (node.nodeType === Node.TEXT_NODE) return node;
                for (const child of node.childNodes) {
                    const result = this.getFirstTextNode(child);
                    if (result) return result;
                }
                return null;
            },

            getLastTextNode: function(node) {
                if (node.nodeType === Node.TEXT_NODE) return node;
                for (let i = node.childNodes.length - 1; i >= 0; i--) {
                    const result = this.getLastTextNode(node.childNodes[i]);
                    if (result) return result;
                }
                return null;
            },

            getSurroundingContext: function(range, contextLength) {
                const body = document.body;
                const fullText = body.textContent || '';
                const preRange = document.createRange();
                preRange.setStart(body, 0);
                preRange.setEnd(range.startContainer, range.startOffset);
                const startPos = preRange.toString().length;
                const endPos = startPos + range.toString().length;
                const contextStart = Math.max(0, startPos - contextLength);
                const contextEnd = Math.min(fullText.length, endPos + contextLength);
                return fullText.substring(contextStart, contextEnd);
            }
        };
        """
    }

    private func highlighterScript() -> String {
        """
        const CruxHighlighter = {
            highlights: new Map(),

            findNodeByPath: function(path) {
                const parts = path.split('/').filter(p => p !== '');
                let current = document.body;
                for (const part of parts) {
                    const index = parseInt(part, 10);
                    if (isNaN(index)) return null;
                    const children = Array.from(current.childNodes).filter(c =>
                        c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
                    );
                    if (index < 1 || index > children.length) return null;
                    current = children[index - 1];
                }
                return current;
            },

            applyHighlight: function(data) {
                const { id, startPath, startOffset, endPath, endOffset } = data;
                const startNode = this.findNodeByPath(startPath);
                const endNode = this.findNodeByPath(endPath);

                if (!startNode || !endNode) return false;
                if (startNode.nodeType !== Node.TEXT_NODE || endNode.nodeType !== Node.TEXT_NODE) return false;
                if (startOffset > startNode.textContent.length || endOffset > endNode.textContent.length) return false;

                try {
                    const range = document.createRange();
                    range.setStart(startNode, startOffset);
                    range.setEnd(endNode, endOffset);

                    if (range.startContainer === range.endContainer) {
                        const span = document.createElement('span');
                        span.className = 'crux-highlight';
                        span.dataset.highlightId = id;
                        range.surroundContents(span);
                        span.addEventListener('click', () => {
                            CruxHighlighter.scrollHighlightToActiveZone(id);
                        });
                        this.highlights.set(id, [span]);
                    } else {
                        // Cross-element: wrap each text node portion
                        const walker = document.createTreeWalker(
                            range.commonAncestorContainer,
                            NodeFilter.SHOW_TEXT,
                            null,
                            false
                        );
                        const textNodes = [];
                        let started = false;
                        let node;
                        while (node = walker.nextNode()) {
                            if (node === range.startContainer) started = true;
                            if (started) textNodes.push(node);
                            if (node === range.endContainer) break;
                        }

                        const elements = [];
                        for (let i = 0; i < textNodes.length; i++) {
                            const textNode = textNodes[i];
                            let start = (i === 0) ? range.startOffset : 0;
                            let end = (i === textNodes.length - 1) ? range.endOffset : textNode.textContent.length;

                            if (start === 0 && end === textNode.textContent.length) {
                                const span = document.createElement('span');
                                span.className = 'crux-highlight';
                                span.dataset.highlightId = id;
                                span.textContent = textNode.textContent;
                                textNode.parentNode.replaceChild(span, textNode);
                                span.addEventListener('click', () => {
                                    window.webkit.messageHandlers.highlightTapped.postMessage(id);
                                });
                                elements.push(span);
                            } else {
                                const before = textNode.textContent.substring(0, start);
                                const middle = textNode.textContent.substring(start, end);
                                const after = textNode.textContent.substring(end);

                                const frag = document.createDocumentFragment();
                                if (before) frag.appendChild(document.createTextNode(before));
                                const span = document.createElement('span');
                                span.className = 'crux-highlight';
                                span.dataset.highlightId = id;
                                span.textContent = middle;
                                span.addEventListener('click', () => {
                                    window.webkit.messageHandlers.highlightTapped.postMessage(id);
                                });
                                frag.appendChild(span);
                                if (after) frag.appendChild(document.createTextNode(after));
                                textNode.parentNode.replaceChild(frag, textNode);
                                elements.push(span);
                            }
                        }
                        this.highlights.set(id, elements);
                    }
                    return true;
                } catch (e) {
                    console.error('Error applying highlight:', e);
                    return false;
                }
            },

            applyHighlights: function(highlightsArray) {
                for (const h of highlightsArray) {
                    this.applyHighlight(h);
                }
            },

            clearAllHighlights: function() {
                for (const [id, elements] of this.highlights) {
                    for (const span of elements) {
                        const parent = span.parentNode;
                        if (parent) {
                            while (span.firstChild) parent.insertBefore(span.firstChild, span);
                            parent.removeChild(span);
                            parent.normalize();
                        }
                    }
                }
                this.highlights.clear();
            },

            removeHighlight: function(highlightId) {
                const elements = this.highlights.get(highlightId);
                if (!elements) return;
                for (const span of elements) {
                    const parent = span.parentNode;
                    if (parent) {
                        while (span.firstChild) parent.insertBefore(span.firstChild, span);
                        parent.removeChild(span);
                        parent.normalize();
                    }
                }
                this.highlights.delete(highlightId);
            },

            getAllHighlightPositions: function() {
                const results = [];

                for (const [id, elements] of this.highlights) {
                    if (elements.length === 0) continue;

                    // Get first element's position (where note should anchor)
                    const firstEl = elements[0];
                    const rect = firstEl.getBoundingClientRect();

                    results.push({
                        id: id,
                        viewportY: rect.top,
                        height: rect.height
                    });
                }

                // Sort by vertical position (top to bottom)
                results.sort((a, b) => a.viewportY - b.viewportY);

                return results;
            },

            reportHighlightPositions: function() {
                const positions = this.getAllHighlightPositions();
                window.webkit.messageHandlers.highlightPositions.postMessage(positions);
            },

            scrollHighlightToActiveZone: function(highlightId, offset = 80) {
                const elements = this.highlights.get(highlightId);
                if (!elements || elements.length === 0) return;

                const firstEl = elements[0];
                const rect = firstEl.getBoundingClientRect();
                const scrollTarget = window.scrollY + rect.top - offset;

                window.scrollTo({
                    top: Math.max(0, scrollTarget),
                    behavior: 'smooth'
                });
            }
        };
        """
    }

    private func selectionScript() -> String {
        """
        document.addEventListener('mouseup', function(e) {
            // Ignore selections within margin notes
            if (e.target.closest('.crux-margin-note') || e.target.closest('.crux-margin')) {
                return;
            }
            const cfiData = CruxCFI.getSelectionCFI();
            if (cfiData && cfiData.text.length > 0) {
                window.webkit.messageHandlers.textSelection.postMessage(cfiData);
            }
        });
        """
    }

    private func scrollListenerScript() -> String {
        """
        (function() {
            // No longer needed for position reporting - margin notes are in HTML
        })();
        """
    }

    private func marginNotesScript() -> String {
        """
        const CruxMarginNotes = {
            notes: new Map(),
            marginColumn: null,

            init: function() {
                this.marginColumn = document.querySelector('.crux-margin');
                this.setupEventDelegation();
            },

            setupEventDelegation: function() {
                document.addEventListener('click', (e) => {
                    const deleteBtn = e.target.closest('.crux-delete-highlight');
                    if (deleteBtn) {
                        const note = deleteBtn.closest('.crux-margin-note');
                        const highlightId = note.dataset.highlightId;
                        window.webkit.messageHandlers.marginNoteAction.postMessage({
                            action: 'deleteHighlight',
                            highlightId: highlightId
                        });
                        // Immediately remove from DOM for responsive feel
                        CruxHighlighter.removeHighlight(highlightId);
                        this.removeNote(highlightId);
                        return;
                    }

                    const startBtn = e.target.closest('.crux-start-thread');
                    if (startBtn) {
                        const note = startBtn.closest('.crux-margin-note');
                        window.webkit.messageHandlers.marginNoteAction.postMessage({
                            action: 'startThread',
                            highlightId: note.dataset.highlightId
                        });
                        return;
                    }

                    const sendBtn = e.target.closest('.crux-send-followup');
                    if (sendBtn) {
                        const note = sendBtn.closest('.crux-margin-note');
                        const input = note.querySelector('.crux-followup-input input');
                        if (input && input.value.trim()) {
                            window.webkit.messageHandlers.marginNoteAction.postMessage({
                                action: 'sendFollowUp',
                                highlightId: note.dataset.highlightId,
                                message: input.value
                            });
                            input.value = '';
                        }
                        return;
                    }
                });

                document.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') {
                        const input = e.target.closest('.crux-followup-input input');
                        if (input && input.value.trim()) {
                            const note = input.closest('.crux-margin-note');
                            window.webkit.messageHandlers.marginNoteAction.postMessage({
                                action: 'sendFollowUp',
                                highlightId: note.dataset.highlightId,
                                message: input.value
                            });
                            input.value = '';
                        }
                    }
                });
            },

            createNoteForHighlight: function(highlightId, preview) {
                const highlight = document.querySelector('[data-highlight-id=\"' + highlightId + '\"]');
                if (!highlight || !this.marginColumn) return;

                this.removeNote(highlightId);

                const top = this.getDocumentOffset(highlight);

                const note = document.createElement('div');
                note.className = 'crux-margin-note';
                note.dataset.highlightId = highlightId;
                note.dataset.idealTop = top;
                note.style.top = top + 'px';

                note.innerHTML = '<div class=\"preview\">' + this.escapeHTML(preview) + '</div>' +
                    '<button class=\"crux-start-thread\">✨ Annotate</button>';

                this.marginColumn.appendChild(note);
                this.notes.set(highlightId, note);

                requestAnimationFrame(() => this.resolveCollisions());
            },

            updateNotes: function(notesData) {
                for (const data of notesData) {
                    let note = this.notes.get(data.highlightId);

                    if (!note) {
                        const highlight = document.querySelector('[data-highlight-id=\"' + data.highlightId + '\"]');
                        if (!highlight || !this.marginColumn) continue;

                        note = document.createElement('div');
                        note.className = 'crux-margin-note';
                        note.dataset.highlightId = data.highlightId;
                        note.dataset.idealTop = this.getDocumentOffset(highlight);
                        note.style.top = note.dataset.idealTop + 'px';
                        this.marginColumn.appendChild(note);
                        this.notes.set(data.highlightId, note);
                    }

                    note.innerHTML = this.buildNoteContent(data);
                }

                requestAnimationFrame(() => this.resolveCollisions());
            },

            buildNoteContent: function(data) {
                let html = '<div class=\"note-header\"><div class=\"preview\">' + this.escapeHTML(data.previewText) + '</div>';
                html += '<button class=\"crux-delete-highlight\" title=\"Delete\">×</button></div>';

                if (data.isLoading) {
                    html += '<div class=\"crux-loading\">' + (data.hasThread ? 'Thinking...' : 'Analyzing...') + '</div>';
                } else if (data.hasThread && data.threadContent) {
                    html += '<div class=\"thread-content\">' + data.threadContent + '</div>';
                    html += '<div class=\"crux-followup-input\">' +
                        '<input type=\"text\" placeholder=\"Follow up...\" />' +
                        '<button class=\"crux-send-followup\">↑</button>' +
                        '</div>';
                } else {
                    html += '<button class=\"crux-start-thread\">✨ Annotate</button>';
                }

                return html;
            },

            removeNote: function(highlightId) {
                const note = this.notes.get(highlightId);
                if (note) {
                    note.remove();
                    this.notes.delete(highlightId);
                }
            },

            clearAllNotes: function() {
                for (const note of this.notes.values()) {
                    note.remove();
                }
                this.notes.clear();
            },

            getDocumentOffset: function(el) {
                let top = 0;
                let current = el;
                while (current && current !== document.body) {
                    top += current.offsetTop;
                    current = current.offsetParent;
                }
                return top;
            },

            resolveCollisions: function() {
                if (!this.marginColumn) return;

                const notesList = Array.from(this.notes.values())
                    .map(el => ({
                        el: el,
                        idealTop: parseFloat(el.dataset.idealTop) || 0,
                        height: el.offsetHeight
                    }))
                    .sort((a, b) => a.idealTop - b.idealTop);

                const GAP = 8;
                let lastBottom = 0;

                for (const note of notesList) {
                    const resolvedTop = Math.max(note.idealTop, lastBottom);
                    note.el.style.top = resolvedTop + 'px';
                    lastBottom = resolvedTop + note.height + GAP;
                }
            },

            escapeHTML: function(str) {
                const div = document.createElement('div');
                div.textContent = str;
                return div.innerHTML;
            }
        };

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => CruxMarginNotes.init());
        } else {
            CruxMarginNotes.init();
        }
        """
    }

    private func wrapWithStyles(_ html: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                :root {
                    --crux-bg: #FFFFFF;
                    --crux-text: #2C2825;
                    --crux-text-muted: #6B6561;
                    --crux-accent: #8B4513;
                    --crux-selection: rgba(139, 69, 19, 0.18);
                    --crux-rule: rgba(44, 40, 37, 0.12);
                    --crux-highlight: rgba(139, 69, 19, 0.15);
                    --crux-highlight-hover: rgba(139, 69, 19, 0.25);
                    --crux-font-body: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
                    --crux-font-display: "New York", "Iowan Old Style", Georgia, serif;
                    --crux-font-ui: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --crux-bg: #1C1A18;
                        --crux-text: #E8E4DF;
                        --crux-text-muted: #9A958F;
                        --crux-accent: #D4A574;
                        --crux-selection: rgba(212, 165, 116, 0.25);
                        --crux-rule: rgba(232, 228, 223, 0.1);
                        --crux-highlight: rgba(212, 165, 116, 0.2);
                        --crux-highlight-hover: rgba(212, 165, 116, 0.35);
                    }
                }
                html, body {
                    margin: 0;
                    padding: 0;
                    background: var(--crux-bg);
                    -webkit-font-smoothing: antialiased;
                }
                .crux-reader-wrapper {
                    display: flex;
                    max-width: 1100px;
                    margin: 0 auto;
                }
                .crux-content {
                    flex: 1;
                    max-width: 680px;
                    padding: 48px 56px;
                    font-family: var(--crux-font-body);
                    font-size: 18px;
                    line-height: 1.75;
                    letter-spacing: 0.01em;
                    color: var(--crux-text);
                    text-rendering: optimizeLegibility;
                    font-feature-settings: "kern" 1, "liga" 1;
                }
                .crux-margin {
                    flex: 0 0 300px;
                    position: relative;
                    padding: 48px 16px 48px 0;
                }

                /* Paragraphs */
                .crux-content p {
                    margin: 0 0 1.5em 0;
                    text-align: justify;
                    hyphens: auto;
                    -webkit-hyphens: auto;
                }
                .crux-content p + p {
                    text-indent: 1.5em;
                    margin-top: -0.5em;
                }

                /* Headings */
                .crux-content h1, .crux-content h2, .crux-content h3, .crux-content h4 {
                    font-family: var(--crux-font-display);
                    font-weight: 500;
                    letter-spacing: -0.01em;
                    line-height: 1.25;
                    margin: 2em 0 0.75em 0;
                    color: var(--crux-text);
                    text-indent: 0;
                }
                .crux-content h1 {
                    font-size: 2em;
                    font-weight: 400;
                    letter-spacing: -0.02em;
                    margin-top: 0;
                    margin-bottom: 1.5em;
                    text-align: center;
                }
                .crux-content h2 {
                    font-size: 1.4em;
                    margin-top: 2.5em;
                    padding-top: 1.5em;
                    border-top: 1px solid var(--crux-rule);
                }
                .crux-content h3 {
                    font-size: 1.15em;
                    font-style: italic;
                    font-weight: 400;
                }

                /* Blockquotes */
                .crux-content blockquote {
                    margin: 2em 0;
                    padding: 0 0 0 1.5em;
                    border-left: 2px solid var(--crux-rule);
                    font-style: italic;
                    color: var(--crux-text-muted);
                }
                .crux-content blockquote p { text-indent: 0; text-align: left; }
                .crux-content h1 + blockquote, .crux-content h2 + blockquote {
                    border-left: none;
                    padding: 0;
                    margin: -0.5em 2em 2.5em 2em;
                    text-align: right;
                    font-size: 0.9em;
                }

                /* Links */
                .crux-content a {
                    color: inherit;
                    text-decoration-color: var(--crux-accent);
                    text-decoration-thickness: 1px;
                    text-underline-offset: 0.15em;
                }

                /* Lists */
                .crux-content ul, .crux-content ol { margin: 1.5em 0; padding-left: 1.5em; }
                .crux-content li { margin-bottom: 0.5em; text-indent: 0; }
                .crux-content li::marker { color: var(--crux-text-muted); }

                /* Horizontal rules */
                .crux-content hr {
                    border: none;
                    margin: 3em auto;
                    text-align: center;
                    color: var(--crux-text-muted);
                }
                .crux-content hr::before {
                    content: "•  •  •";
                    letter-spacing: 0.5em;
                }

                /* Images */
                .crux-content img { max-width: 100%; height: auto; display: block; margin: 2em auto; }

                /* Selection */
                ::selection { background: var(--crux-selection); }

                /* Highlights */
                .crux-highlight {
                    background-color: var(--crux-highlight);
                    border-radius: 2px;
                    cursor: pointer;
                    transition: background-color 0.2s ease;
                }
                .crux-highlight:hover { background-color: var(--crux-highlight-hover); }

                /* Margin notes */
                .crux-margin-note {
                    position: absolute;
                    right: 16px;
                    width: 268px;
                    padding: 12px;
                    background: var(--crux-rule);
                    border-radius: 6px;
                    font-family: var(--crux-font-ui);
                    font-size: 13px;
                    line-height: 1.5;
                    color: var(--crux-text);
                }
                .crux-margin-note .note-header {
                    display: flex;
                    justify-content: space-between;
                    align-items: flex-start;
                    gap: 8px;
                    margin-bottom: 10px;
                }
                .crux-margin-note .preview {
                    flex: 1;
                    font-family: var(--crux-font-body);
                    font-style: italic;
                    color: var(--crux-text-muted);
                    font-size: 12px;
                    display: -webkit-box;
                    -webkit-line-clamp: 2;
                    -webkit-box-orient: vertical;
                    overflow: hidden;
                }
                .crux-delete-highlight {
                    appearance: none;
                    border: none;
                    background: transparent;
                    color: var(--crux-text-muted);
                    font-size: 16px;
                    line-height: 1;
                    padding: 0 4px;
                    cursor: pointer;
                    opacity: 0.5;
                    transition: opacity 0.15s ease;
                }
                .crux-delete-highlight:hover {
                    opacity: 1;
                    color: var(--crux-accent);
                }
                .crux-margin-note .thread-content { margin-bottom: 8px; }
                .crux-margin-note .thread-message { margin-bottom: 10px; }
                .crux-margin-note .thread-message.user {
                    font-style: italic;
                    color: var(--crux-text-muted);
                    font-size: 12px;
                }
                .crux-margin-note .thread-message.user::before { content: "You: "; font-weight: 500; }
                .crux-margin-note .thread-message.assistant { color: var(--crux-text); }
                .crux-margin-note .thread-message strong { font-weight: 600; }
                .crux-margin-note .thread-message em { font-style: italic; }
                .crux-margin-note .thread-message code {
                    font-family: ui-monospace, "SF Mono", Menlo, monospace;
                    font-size: 0.9em;
                    background: var(--crux-rule);
                    padding: 1px 4px;
                    border-radius: 3px;
                }
                .crux-start-thread, .crux-send-followup {
                    appearance: none;
                    border: 1px solid var(--crux-rule);
                    background: var(--crux-bg);
                    border-radius: 5px;
                    padding: 6px 10px;
                    font-size: 12px;
                    font-family: var(--crux-font-ui);
                    color: var(--crux-text);
                    cursor: pointer;
                }
                .crux-start-thread:hover, .crux-send-followup:hover {
                    background: var(--crux-rule);
                }
                .crux-followup-input { display: flex; gap: 4px; margin-top: 10px; }
                .crux-followup-input input {
                    flex: 1;
                    border: 1px solid var(--crux-rule);
                    border-radius: 5px;
                    padding: 6px 8px;
                    font-size: 12px;
                    font-family: var(--crux-font-ui);
                    background: var(--crux-bg);
                    color: var(--crux-text);
                }
                .crux-loading {
                    display: flex;
                    align-items: center;
                    gap: 6px;
                    color: var(--crux-text-muted);
                    font-size: 12px;
                }
                .crux-loading::before {
                    content: "";
                    width: 12px;
                    height: 12px;
                    border: 2px solid var(--crux-rule);
                    border-top-color: var(--crux-accent);
                    border-radius: 50%;
                    animation: spin 0.8s linear infinite;
                }
                @keyframes spin { to { transform: rotate(360deg); } }
            </style>
        </head>
        <body>
            <div class="crux-reader-wrapper">
                <div class="crux-content">
                    \(html)
                </div>
                <div class="crux-margin"></div>
            </div>
        </body>
        </html>
        """
    }
}
#else
struct WebViewRepresentable: UIViewRepresentable {
    let html: String
    let highlights: [Highlight]
    let marginNotes: [MarginNoteData]
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    let onMarginNoteAction: ((MarginNoteAction) -> Void)?

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelection")
        config.userContentController.add(context.coordinator, name: "highlightTapped")
        config.userContentController.add(context.coordinator, name: "marginNoteAction")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Inject all scripts
        let script = cfiScript() + "\n\n" + highlighterScript() + "\n\n" + selectionScript() + "\n\n" + marginNotesScript()
        let userScript = WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(userScript)

        // Load initial content
        let styledHTML = wrapWithStyles(html)
        webView.loadHTMLString(styledHTML, baseURL: nil)
        context.coordinator.lastLoadedHTML = html
        context.coordinator.pendingHighlights = highlights
        context.coordinator.pendingMarginNotes = marginNotes
        context.coordinator.webView = webView

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != html {
            let styledHTML = wrapWithStyles(html)
            webView.loadHTMLString(styledHTML, baseURL: nil)
            context.coordinator.lastLoadedHTML = html
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            context.coordinator.highlightsApplied = []
        } else if Set(context.coordinator.highlightsApplied) != Set(highlights.compactMap { $0.cfiRange != nil ? $0.id : nil }) {
            // Also update pendingHighlights in case the page is still loading
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            context.coordinator.applyHighlights(highlights, to: webView)
        }

        // Update margin notes if they changed
        if context.coordinator.lastMarginNotes != marginNotes {
            context.coordinator.updateMarginNotes(marginNotes)
            context.coordinator.lastMarginNotes = marginNotes
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction
        )
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let onTextSelected: (SelectionData) -> Void
        let onHighlightTapped: (UUID) -> Void
        let onMarginNoteAction: ((MarginNoteAction) -> Void)?
        var lastLoadedHTML: String = ""
        var pendingHighlights: [Highlight] = []
        var pendingMarginNotes: [MarginNoteData] = []
        var highlightsApplied: [UUID] = []
        var lastMarginNotes: [MarginNoteData] = []
        weak var webView: WKWebView?

        init(
            onTextSelected: @escaping (SelectionData) -> Void,
            onHighlightTapped: @escaping (UUID) -> Void,
            onMarginNoteAction: ((MarginNoteAction) -> Void)?
        ) {
            self.onTextSelected = onTextSelected
            self.onHighlightTapped = onHighlightTapped
            self.onMarginNoteAction = onMarginNoteAction
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Apply highlights and margin notes after page loads
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.applyHighlights(self.pendingHighlights, to: webView)
                // Apply pending margin notes after highlights
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.updateMarginNotes(self.pendingMarginNotes)
                }
            }
        }

        func applyHighlights(_ highlights: [Highlight], to webView: WKWebView) {
            let highlightsWithCFI = highlights.compactMap { h -> [String: Any]? in
                guard let cfi = h.cfiRange else { return nil }
                return [
                    "id": h.id.uuidString,
                    "startPath": cfi.startPath,
                    "startOffset": cfi.startOffset,
                    "endPath": cfi.endPath,
                    "endOffset": cfi.endOffset
                ]
            }

            guard !highlightsWithCFI.isEmpty,
                  let jsonData = try? JSONSerialization.data(withJSONObject: highlightsWithCFI),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            webView.evaluateJavaScript("CruxHighlighter.applyHighlights(\(jsonString));") { [weak self] _, error in
                if error == nil {
                    self?.highlightsApplied = highlightsWithCFI.compactMap { UUID(uuidString: $0["id"] as? String ?? "") }
                }
            }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "textSelection", let body = message.body as? [String: Any] {
                guard let text = body["text"] as? String, !text.isEmpty,
                      let startPath = body["startPath"] as? String,
                      let startOffset = body["startOffset"] as? Int,
                      let endPath = body["endPath"] as? String,
                      let endOffset = body["endOffset"] as? Int else { return }

                let context = body["context"] as? String ?? ""
                let cfiRange = CFIRange(
                    startPath: startPath,
                    startOffset: startOffset,
                    endPath: endPath,
                    endOffset: endOffset
                )
                let selectionData = SelectionData(text: text, cfiRange: cfiRange, context: context)

                DispatchQueue.main.async {
                    self.onTextSelected(selectionData)
                }
            } else if message.name == "highlightTapped", let idString = message.body as? String {
                if let uuid = UUID(uuidString: idString) {
                    DispatchQueue.main.async {
                        self.onHighlightTapped(uuid)
                    }
                }
            } else if message.name == "marginNoteAction", let body = message.body as? [String: Any] {
                guard let action = body["action"] as? String,
                      let idString = body["highlightId"] as? String,
                      let highlightId = UUID(uuidString: idString) else { return }

                let noteAction: MarginNoteAction
                switch action {
                case "startThread":
                    noteAction = .startThread(highlightId: highlightId)
                case "sendFollowUp":
                    let message = body["message"] as? String ?? ""
                    noteAction = .sendFollowUp(highlightId: highlightId, message: message)
                case "deleteHighlight":
                    noteAction = .deleteHighlight(highlightId: highlightId)
                default:
                    return
                }

                DispatchQueue.main.async {
                    self.onMarginNoteAction?(noteAction)
                }
            }
        }

        /// Updates margin notes in the WebView with thread content
        func updateMarginNotes(_ notes: [MarginNoteData]) {
            guard let webView = webView,
                  let jsonData = try? JSONEncoder().encode(notes),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let js = "CruxMarginNotes.updateNotes(\(jsonString));"
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }

    // MARK: - JavaScript (same as macOS)

    private func cfiScript() -> String {
        """
        const CruxCFI = {
            getPathToNode: function(node) {
                const path = [];
                let current = node;
                while (current && current !== document.body && current.parentNode) {
                    const parent = current.parentNode;
                    const children = Array.from(parent.childNodes).filter(c =>
                        c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
                    );
                    let position = 0;
                    for (let i = 0; i < children.length; i++) {
                        position++;
                        if (children[i] === current) break;
                    }
                    path.unshift(position);
                    current = parent;
                }
                return '/' + path.join('/');
            },

            getSelectionCFI: function() {
                const selection = window.getSelection();
                if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;

                const range = selection.getRangeAt(0);
                const text = selection.toString().trim();
                if (!text) return null;

                let startNode = range.startContainer;
                let endNode = range.endContainer;

                if (startNode.nodeType !== Node.TEXT_NODE) {
                    startNode = this.getFirstTextNode(startNode);
                }
                if (endNode.nodeType !== Node.TEXT_NODE) {
                    endNode = this.getLastTextNode(endNode);
                }
                if (!startNode || !endNode) return null;

                const context = this.getSurroundingContext(range, 500);

                return {
                    startPath: this.getPathToNode(startNode),
                    startOffset: range.startOffset,
                    endPath: this.getPathToNode(endNode),
                    endOffset: range.endOffset,
                    text: text,
                    context: context
                };
            },

            getFirstTextNode: function(node) {
                if (node.nodeType === Node.TEXT_NODE) return node;
                for (const child of node.childNodes) {
                    const result = this.getFirstTextNode(child);
                    if (result) return result;
                }
                return null;
            },

            getLastTextNode: function(node) {
                if (node.nodeType === Node.TEXT_NODE) return node;
                for (let i = node.childNodes.length - 1; i >= 0; i--) {
                    const result = this.getLastTextNode(node.childNodes[i]);
                    if (result) return result;
                }
                return null;
            },

            getSurroundingContext: function(range, contextLength) {
                const body = document.body;
                const fullText = body.textContent || '';
                const preRange = document.createRange();
                preRange.setStart(body, 0);
                preRange.setEnd(range.startContainer, range.startOffset);
                const startPos = preRange.toString().length;
                const endPos = startPos + range.toString().length;
                const contextStart = Math.max(0, startPos - contextLength);
                const contextEnd = Math.min(fullText.length, endPos + contextLength);
                return fullText.substring(contextStart, contextEnd);
            }
        };
        """
    }

    private func highlighterScript() -> String {
        """
        const CruxHighlighter = {
            highlights: new Map(),

            findNodeByPath: function(path) {
                const parts = path.split('/').filter(p => p !== '');
                let current = document.body;
                for (const part of parts) {
                    const index = parseInt(part, 10);
                    if (isNaN(index)) return null;
                    const children = Array.from(current.childNodes).filter(c =>
                        c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
                    );
                    if (index < 1 || index > children.length) return null;
                    current = children[index - 1];
                }
                return current;
            },

            applyHighlight: function(data) {
                const { id, startPath, startOffset, endPath, endOffset } = data;
                const startNode = this.findNodeByPath(startPath);
                const endNode = this.findNodeByPath(endPath);

                if (!startNode || !endNode) return false;
                if (startNode.nodeType !== Node.TEXT_NODE || endNode.nodeType !== Node.TEXT_NODE) return false;
                if (startOffset > startNode.textContent.length || endOffset > endNode.textContent.length) return false;

                try {
                    const range = document.createRange();
                    range.setStart(startNode, startOffset);
                    range.setEnd(endNode, endOffset);

                    if (range.startContainer === range.endContainer) {
                        const span = document.createElement('span');
                        span.className = 'crux-highlight';
                        span.dataset.highlightId = id;
                        range.surroundContents(span);
                        span.addEventListener('click', () => {
                            CruxHighlighter.scrollHighlightToActiveZone(id);
                        });
                        this.highlights.set(id, [span]);
                    } else {
                        const walker = document.createTreeWalker(
                            range.commonAncestorContainer,
                            NodeFilter.SHOW_TEXT,
                            null,
                            false
                        );
                        const textNodes = [];
                        let started = false;
                        let node;
                        while (node = walker.nextNode()) {
                            if (node === range.startContainer) started = true;
                            if (started) textNodes.push(node);
                            if (node === range.endContainer) break;
                        }

                        const elements = [];
                        for (let i = 0; i < textNodes.length; i++) {
                            const textNode = textNodes[i];
                            let start = (i === 0) ? range.startOffset : 0;
                            let end = (i === textNodes.length - 1) ? range.endOffset : textNode.textContent.length;

                            if (start === 0 && end === textNode.textContent.length) {
                                const span = document.createElement('span');
                                span.className = 'crux-highlight';
                                span.dataset.highlightId = id;
                                span.textContent = textNode.textContent;
                                textNode.parentNode.replaceChild(span, textNode);
                                span.addEventListener('click', () => {
                                    window.webkit.messageHandlers.highlightTapped.postMessage(id);
                                });
                                elements.push(span);
                            } else {
                                const before = textNode.textContent.substring(0, start);
                                const middle = textNode.textContent.substring(start, end);
                                const after = textNode.textContent.substring(end);

                                const frag = document.createDocumentFragment();
                                if (before) frag.appendChild(document.createTextNode(before));
                                const span = document.createElement('span');
                                span.className = 'crux-highlight';
                                span.dataset.highlightId = id;
                                span.textContent = middle;
                                span.addEventListener('click', () => {
                                    window.webkit.messageHandlers.highlightTapped.postMessage(id);
                                });
                                frag.appendChild(span);
                                if (after) frag.appendChild(document.createTextNode(after));
                                textNode.parentNode.replaceChild(frag, textNode);
                                elements.push(span);
                            }
                        }
                        this.highlights.set(id, elements);
                    }
                    return true;
                } catch (e) {
                    console.error('Error applying highlight:', e);
                    return false;
                }
            },

            applyHighlights: function(highlightsArray) {
                for (const h of highlightsArray) {
                    this.applyHighlight(h);
                }
            },

            clearAllHighlights: function() {
                for (const [id, elements] of this.highlights) {
                    for (const span of elements) {
                        const parent = span.parentNode;
                        if (parent) {
                            while (span.firstChild) parent.insertBefore(span.firstChild, span);
                            parent.removeChild(span);
                            parent.normalize();
                        }
                    }
                }
                this.highlights.clear();
            },

            removeHighlight: function(highlightId) {
                const elements = this.highlights.get(highlightId);
                if (!elements) return;
                for (const span of elements) {
                    const parent = span.parentNode;
                    if (parent) {
                        while (span.firstChild) parent.insertBefore(span.firstChild, span);
                        parent.removeChild(span);
                        parent.normalize();
                    }
                }
                this.highlights.delete(highlightId);
            },

            getAllHighlightPositions: function() {
                const results = [];

                for (const [id, elements] of this.highlights) {
                    if (elements.length === 0) continue;

                    // Get first element's position (where note should anchor)
                    const firstEl = elements[0];
                    const rect = firstEl.getBoundingClientRect();

                    results.push({
                        id: id,
                        viewportY: rect.top,
                        height: rect.height
                    });
                }

                // Sort by vertical position (top to bottom)
                results.sort((a, b) => a.viewportY - b.viewportY);

                return results;
            },

            reportHighlightPositions: function() {
                const positions = this.getAllHighlightPositions();
                window.webkit.messageHandlers.highlightPositions.postMessage(positions);
            },

            scrollHighlightToActiveZone: function(highlightId, offset = 80) {
                const elements = this.highlights.get(highlightId);
                if (!elements || elements.length === 0) return;

                const firstEl = elements[0];
                const rect = firstEl.getBoundingClientRect();
                const scrollTarget = window.scrollY + rect.top - offset;

                window.scrollTo({
                    top: Math.max(0, scrollTarget),
                    behavior: 'smooth'
                });
            }
        };
        """
    }

    private func selectionScript() -> String {
        """
        document.addEventListener('selectionchange', function() {
            // Ignore selections within margin notes
            const selection = window.getSelection();
            if (selection && selection.anchorNode) {
                const anchor = selection.anchorNode.nodeType === Node.TEXT_NODE
                    ? selection.anchorNode.parentElement
                    : selection.anchorNode;
                if (anchor && (anchor.closest('.crux-margin-note') || anchor.closest('.crux-margin'))) {
                    return;
                }
            }
            const cfiData = CruxCFI.getSelectionCFI();
            if (cfiData && cfiData.text.length > 0) {
                window.webkit.messageHandlers.textSelection.postMessage(cfiData);
            }
        });
        """
    }

    private func marginNotesScript() -> String {
        """
        const CruxMarginNotes = {
            notes: new Map(),
            marginColumn: null,

            init: function() {
                this.marginColumn = document.querySelector('.crux-margin');
                this.setupEventDelegation();
            },

            setupEventDelegation: function() {
                document.addEventListener('click', (e) => {
                    const deleteBtn = e.target.closest('.crux-delete-highlight');
                    if (deleteBtn) {
                        const note = deleteBtn.closest('.crux-margin-note');
                        const highlightId = note.dataset.highlightId;
                        window.webkit.messageHandlers.marginNoteAction.postMessage({
                            action: 'deleteHighlight',
                            highlightId: highlightId
                        });
                        // Immediately remove from DOM for responsive feel
                        CruxHighlighter.removeHighlight(highlightId);
                        this.removeNote(highlightId);
                        return;
                    }

                    const startBtn = e.target.closest('.crux-start-thread');
                    if (startBtn) {
                        const note = startBtn.closest('.crux-margin-note');
                        window.webkit.messageHandlers.marginNoteAction.postMessage({
                            action: 'startThread',
                            highlightId: note.dataset.highlightId
                        });
                        return;
                    }

                    const sendBtn = e.target.closest('.crux-send-followup');
                    if (sendBtn) {
                        const note = sendBtn.closest('.crux-margin-note');
                        const input = note.querySelector('.crux-followup-input input');
                        if (input && input.value.trim()) {
                            window.webkit.messageHandlers.marginNoteAction.postMessage({
                                action: 'sendFollowUp',
                                highlightId: note.dataset.highlightId,
                                message: input.value
                            });
                            input.value = '';
                        }
                        return;
                    }
                });

                document.addEventListener('keydown', (e) => {
                    if (e.key === 'Enter') {
                        const input = e.target.closest('.crux-followup-input input');
                        if (input && input.value.trim()) {
                            const note = input.closest('.crux-margin-note');
                            window.webkit.messageHandlers.marginNoteAction.postMessage({
                                action: 'sendFollowUp',
                                highlightId: note.dataset.highlightId,
                                message: input.value
                            });
                            input.value = '';
                        }
                    }
                });
            },

            createNoteForHighlight: function(highlightId, preview) {
                const highlight = document.querySelector('[data-highlight-id="' + highlightId + '"]');
                if (!highlight || !this.marginColumn) return;

                this.removeNote(highlightId);

                const top = this.getDocumentOffset(highlight);

                const note = document.createElement('div');
                note.className = 'crux-margin-note';
                note.dataset.highlightId = highlightId;
                note.dataset.idealTop = top;
                note.style.top = top + 'px';

                note.innerHTML = '<div class="preview">' + this.escapeHTML(preview) + '</div>' +
                    '<button class="crux-start-thread">✨ Annotate</button>';

                this.marginColumn.appendChild(note);
                this.notes.set(highlightId, note);

                requestAnimationFrame(() => this.resolveCollisions());
            },

            updateNotes: function(notesData) {
                for (const data of notesData) {
                    let note = this.notes.get(data.highlightId);

                    if (!note) {
                        const highlight = document.querySelector('[data-highlight-id="' + data.highlightId + '"]');
                        if (!highlight || !this.marginColumn) continue;

                        note = document.createElement('div');
                        note.className = 'crux-margin-note';
                        note.dataset.highlightId = data.highlightId;
                        note.dataset.idealTop = this.getDocumentOffset(highlight);
                        note.style.top = note.dataset.idealTop + 'px';
                        this.marginColumn.appendChild(note);
                        this.notes.set(data.highlightId, note);
                    }

                    note.innerHTML = this.buildNoteContent(data);
                }

                requestAnimationFrame(() => this.resolveCollisions());
            },

            buildNoteContent: function(data) {
                let html = '<div class="preview">' + this.escapeHTML(data.previewText) + '</div>';

                if (data.isLoading) {
                    html += '<div class="crux-loading">' + (data.hasThread ? 'Thinking...' : 'Analyzing...') + '</div>';
                } else if (data.hasThread && data.threadContent) {
                    html += '<div class="thread-content">' + data.threadContent + '</div>';
                    html += '<div class="crux-followup-input">' +
                        '<input type="text" placeholder="Follow up..." />' +
                        '<button class="crux-send-followup">↑</button>' +
                        '</div>';
                } else {
                    html += '<button class="crux-start-thread">✨ Annotate</button>';
                }

                return html;
            },

            removeNote: function(highlightId) {
                const note = this.notes.get(highlightId);
                if (note) {
                    note.remove();
                    this.notes.delete(highlightId);
                }
            },

            clearAllNotes: function() {
                for (const note of this.notes.values()) {
                    note.remove();
                }
                this.notes.clear();
            },

            getDocumentOffset: function(el) {
                let top = 0;
                let current = el;
                while (current && current !== document.body) {
                    top += current.offsetTop;
                    current = current.offsetParent;
                }
                return top;
            },

            resolveCollisions: function() {
                if (!this.marginColumn) return;

                const notesList = Array.from(this.notes.values())
                    .map(el => ({
                        el: el,
                        idealTop: parseFloat(el.dataset.idealTop) || 0,
                        height: el.offsetHeight
                    }))
                    .sort((a, b) => a.idealTop - b.idealTop);

                const GAP = 8;
                let lastBottom = 0;

                for (const note of notesList) {
                    const resolvedTop = Math.max(note.idealTop, lastBottom);
                    note.el.style.top = resolvedTop + 'px';
                    lastBottom = resolvedTop + note.height + GAP;
                }
            },

            escapeHTML: function(str) {
                const div = document.createElement('div');
                div.textContent = str;
                return div.innerHTML;
            }
        };

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => CruxMarginNotes.init());
        } else {
            CruxMarginNotes.init();
        }
        """
    }

    private func wrapWithStyles(_ html: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                :root {
                    --crux-bg: #FFFFFF;
                    --crux-text: #2C2825;
                    --crux-text-muted: #6B6561;
                    --crux-accent: #8B4513;
                    --crux-selection: rgba(139, 69, 19, 0.18);
                    --crux-rule: rgba(44, 40, 37, 0.12);
                    --crux-highlight: rgba(139, 69, 19, 0.15);
                    --crux-highlight-hover: rgba(139, 69, 19, 0.25);
                    --crux-font-body: "Iowan Old Style", "Palatino Linotype", Palatino, Georgia, serif;
                    --crux-font-display: "New York", "Iowan Old Style", Georgia, serif;
                    --crux-font-ui: -apple-system, BlinkMacSystemFont, sans-serif;
                }
                @media (prefers-color-scheme: dark) {
                    :root {
                        --crux-bg: #1C1A18;
                        --crux-text: #E8E4DF;
                        --crux-text-muted: #9A958F;
                        --crux-accent: #D4A574;
                        --crux-selection: rgba(212, 165, 116, 0.25);
                        --crux-rule: rgba(232, 228, 223, 0.1);
                        --crux-highlight: rgba(212, 165, 116, 0.2);
                        --crux-highlight-hover: rgba(212, 165, 116, 0.35);
                    }
                }
                html, body {
                    margin: 0;
                    padding: 0;
                    background: var(--crux-bg);
                    -webkit-font-smoothing: antialiased;
                }
                .crux-reader-wrapper {
                    display: flex;
                    max-width: 1100px;
                    margin: 0 auto;
                }
                .crux-content {
                    flex: 1;
                    max-width: 680px;
                    padding: 24px 20px;
                    font-family: var(--crux-font-body);
                    font-size: 17px;
                    line-height: 1.7;
                    letter-spacing: 0.01em;
                    color: var(--crux-text);
                    text-rendering: optimizeLegibility;
                    font-feature-settings: "kern" 1, "liga" 1;
                }
                .crux-margin {
                    flex: 0 0 280px;
                    position: relative;
                    padding: 24px 12px 24px 0;
                }

                /* Paragraphs */
                .crux-content p {
                    margin: 0 0 1.4em 0;
                    text-align: justify;
                    hyphens: auto;
                    -webkit-hyphens: auto;
                }
                .crux-content p + p {
                    text-indent: 1.5em;
                    margin-top: -0.4em;
                }

                /* Headings */
                .crux-content h1, .crux-content h2, .crux-content h3, .crux-content h4 {
                    font-family: var(--crux-font-display);
                    font-weight: 500;
                    letter-spacing: -0.01em;
                    line-height: 1.25;
                    margin: 1.8em 0 0.7em 0;
                    color: var(--crux-text);
                    text-indent: 0;
                }
                .crux-content h1 {
                    font-size: 1.8em;
                    font-weight: 400;
                    letter-spacing: -0.02em;
                    margin-top: 0;
                    margin-bottom: 1.2em;
                    text-align: center;
                }
                .crux-content h2 {
                    font-size: 1.3em;
                    margin-top: 2em;
                    padding-top: 1.2em;
                    border-top: 1px solid var(--crux-rule);
                }
                .crux-content h3 {
                    font-size: 1.1em;
                    font-style: italic;
                    font-weight: 400;
                }

                /* Blockquotes */
                .crux-content blockquote {
                    margin: 1.5em 0;
                    padding: 0 0 0 1.2em;
                    border-left: 2px solid var(--crux-rule);
                    font-style: italic;
                    color: var(--crux-text-muted);
                }
                .crux-content blockquote p { text-indent: 0; text-align: left; }
                .crux-content h1 + blockquote, .crux-content h2 + blockquote {
                    border-left: none;
                    padding: 0;
                    margin: -0.3em 1.5em 2em 1.5em;
                    text-align: right;
                    font-size: 0.9em;
                }

                /* Links */
                .crux-content a {
                    color: inherit;
                    text-decoration-color: var(--crux-accent);
                    text-decoration-thickness: 1px;
                    text-underline-offset: 0.15em;
                }

                /* Lists */
                .crux-content ul, .crux-content ol { margin: 1.4em 0; padding-left: 1.4em; }
                .crux-content li { margin-bottom: 0.4em; text-indent: 0; }
                .crux-content li::marker { color: var(--crux-text-muted); }

                /* Horizontal rules */
                .crux-content hr {
                    border: none;
                    margin: 2.5em auto;
                    text-align: center;
                    color: var(--crux-text-muted);
                }
                .crux-content hr::before {
                    content: "•  •  •";
                    letter-spacing: 0.5em;
                }

                /* Images */
                .crux-content img { max-width: 100%; height: auto; display: block; margin: 1.5em auto; }

                /* Selection */
                ::selection { background: var(--crux-selection); }

                /* Highlights */
                .crux-highlight {
                    background-color: var(--crux-highlight);
                    border-radius: 2px;
                    cursor: pointer;
                    transition: background-color 0.2s ease;
                }
                .crux-highlight:hover { background-color: var(--crux-highlight-hover); }

                /* Margin notes */
                .crux-margin-note {
                    position: absolute;
                    right: 12px;
                    width: 252px;
                    padding: 10px;
                    background: var(--crux-rule);
                    border-radius: 6px;
                    font-family: var(--crux-font-ui);
                    font-size: 13px;
                    line-height: 1.5;
                    color: var(--crux-text);
                }
                .crux-margin-note .preview {
                    font-family: var(--crux-font-body);
                    font-style: italic;
                    color: var(--crux-text-muted);
                    font-size: 12px;
                    margin-bottom: 8px;
                    display: -webkit-box;
                    -webkit-line-clamp: 2;
                    -webkit-box-orient: vertical;
                    overflow: hidden;
                }
                .crux-margin-note .thread-content { margin-bottom: 8px; }
                .crux-margin-note .thread-message { margin-bottom: 8px; }
                .crux-margin-note .thread-message.user {
                    font-style: italic;
                    color: var(--crux-text-muted);
                    font-size: 12px;
                }
                .crux-margin-note .thread-message.user::before { content: "You: "; font-weight: 500; }
                .crux-margin-note .thread-message.assistant { color: var(--crux-text); }
                .crux-margin-note .thread-message strong { font-weight: 600; }
                .crux-margin-note .thread-message em { font-style: italic; }
                .crux-margin-note .thread-message code {
                    font-family: ui-monospace, "SF Mono", Menlo, monospace;
                    font-size: 0.9em;
                    background: var(--crux-rule);
                    padding: 1px 4px;
                    border-radius: 3px;
                }
                .crux-start-thread, .crux-send-followup {
                    appearance: none;
                    border: 1px solid var(--crux-rule);
                    background: var(--crux-bg);
                    border-radius: 5px;
                    padding: 6px 10px;
                    font-size: 12px;
                    font-family: var(--crux-font-ui);
                    color: var(--crux-text);
                    cursor: pointer;
                }
                .crux-followup-input { display: flex; gap: 4px; margin-top: 8px; }
                .crux-followup-input input {
                    flex: 1;
                    border: 1px solid var(--crux-rule);
                    border-radius: 5px;
                    padding: 6px 8px;
                    font-size: 12px;
                    font-family: var(--crux-font-ui);
                    background: var(--crux-bg);
                    color: var(--crux-text);
                }
                .crux-loading {
                    display: flex;
                    align-items: center;
                    gap: 6px;
                    color: var(--crux-text-muted);
                    font-size: 12px;
                }
                .crux-loading::before {
                    content: "";
                    width: 12px;
                    height: 12px;
                    border: 2px solid var(--crux-rule);
                    border-top-color: var(--crux-accent);
                    border-radius: 50%;
                    animation: spin 0.8s linear infinite;
                }
                @keyframes spin { to { transform: rotate(360deg); } }
            </style>
        </head>
        <body>
            <div class="crux-reader-wrapper">
                <div class="crux-content">
                    \(html)
                </div>
                <div class="crux-margin"></div>
            </div>
        </body>
        </html>
        """
    }
}
#endif
