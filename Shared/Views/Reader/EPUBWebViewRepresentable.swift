import SwiftUI
import WebKit

// MARK: - Platform Type Aliases

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

// MARK: - WebView Representable

struct EPUBWebViewRepresentable: PlatformViewRepresentable {
    let html: String
    let highlights: [Highlight]
    let marginNotes: [MarginNoteData]
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    let onMarginNoteAction: ((MarginNoteAction) -> Void)?
    let onSearchResults: ((Int, Int) -> Void)?
    let onContentLoaded: (() -> Void)?
    let onVisibleSection: ((Int, Double) -> Void)?

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator(
            onTextSelected: onTextSelected,
            onHighlightTapped: onHighlightTapped,
            onMarginNoteAction: onMarginNoteAction,
            onSearchResults: onSearchResults,
            onContentLoaded: onContentLoaded,
            onVisibleSection: onVisibleSection
        )
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }
    #else
    func makeUIView(context: Context) -> WKWebView {
        makeWebView(context: context)
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        updateWebView(webView, context: context)
    }
    #endif

    // MARK: - Shared Implementation

    private func makeWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "textSelection")
        config.userContentController.add(context.coordinator, name: "highlightTapped")
        config.userContentController.add(context.coordinator, name: "marginNoteAction")
        config.userContentController.add(context.coordinator, name: "searchResults")
        config.userContentController.add(context.coordinator, name: "visibleSection")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator

        // Load HTML with bundle base URL for resource loading
        if let styledHTML = ReaderResources.buildHTML(content: html),
           let baseURL = ReaderResources.baseURL {
            webView.loadHTMLString(styledHTML, baseURL: baseURL)
        }

        context.coordinator.lastLoadedHTML = html
        context.coordinator.pendingHighlights = highlights
        context.coordinator.pendingMarginNotes = marginNotes
        context.coordinator.webView = webView

        return webView
    }

    private func updateWebView(_ webView: WKWebView, context: Context) {
        // Only reload if the HTML content actually changed
        if context.coordinator.lastLoadedHTML != html {
            if let styledHTML = ReaderResources.buildHTML(content: html),
               let baseURL = ReaderResources.baseURL {
                webView.loadHTMLString(styledHTML, baseURL: baseURL)
            }
            context.coordinator.lastLoadedHTML = html
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            context.coordinator.highlightsApplied = []
        } else if Set(context.coordinator.highlightsApplied) != Set(highlights.compactMap { $0.cfiRange != nil ? $0.id : nil }) {
            // Highlights changed but HTML didn't - apply new highlights
            context.coordinator.pendingHighlights = highlights
            context.coordinator.pendingMarginNotes = marginNotes
            let currentMarginNotes = marginNotes
            context.coordinator.applyHighlights(highlights, to: webView) {
                context.coordinator.updateMarginNotes(currentMarginNotes)
                context.coordinator.lastMarginNotes = currentMarginNotes
            }
            return
        }

        // Update margin notes if they changed
        if context.coordinator.lastMarginNotes != marginNotes {
            context.coordinator.updateMarginNotes(marginNotes)
            context.coordinator.lastMarginNotes = marginNotes
        }
    }
}

// MARK: - Coordinator

class WebViewCoordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let onTextSelected: (SelectionData) -> Void
    let onHighlightTapped: (UUID) -> Void
    let onMarginNoteAction: ((MarginNoteAction) -> Void)?
    let onSearchResults: ((Int, Int) -> Void)?
    let onContentLoaded: (() -> Void)?
    let onVisibleSection: ((Int, Double) -> Void)?

    var lastLoadedHTML: String = ""
    var pendingHighlights: [Highlight] = []
    var pendingMarginNotes: [MarginNoteData] = []
    var highlightsApplied: [UUID] = []
    var lastMarginNotes: [MarginNoteData] = []
    weak var webView: WKWebView?

    init(
        onTextSelected: @escaping (SelectionData) -> Void,
        onHighlightTapped: @escaping (UUID) -> Void,
        onMarginNoteAction: ((MarginNoteAction) -> Void)?,
        onSearchResults: ((Int, Int) -> Void)?,
        onContentLoaded: (() -> Void)?,
        onVisibleSection: ((Int, Double) -> Void)?
    ) {
        self.onTextSelected = onTextSelected
        self.onHighlightTapped = onHighlightTapped
        self.onMarginNoteAction = onMarginNoteAction
        self.onSearchResults = onSearchResults
        self.onContentLoaded = onContentLoaded
        self.onVisibleSection = onVisibleSection
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        applyHighlights(pendingHighlights, to: webView) { [weak self] in
            self?.updateMarginNotes(self?.pendingMarginNotes ?? [])
            DispatchQueue.main.async {
                self?.onContentLoaded?()
            }
        }
    }

    func applyHighlights(_ highlights: [Highlight], to webView: WKWebView, completion: (() -> Void)? = nil) {
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
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            completion?()
            return
        }

        let js = "CruxHighlighter.applyHighlights(\(jsonString));"
        webView.evaluateJavaScript(js) { [weak self] _, error in
            if error == nil {
                self?.highlightsApplied = highlightsWithCFI.compactMap { UUID(uuidString: $0["id"] as? String ?? "") }
            }
            completion?()
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
            case "commitHighlight":
                noteAction = .commitHighlight(highlightId: highlightId)
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
        } else if message.name == "searchResults", let body = message.body as? [String: Any] {
            let matchCount = body["matchCount"] as? Int ?? 0
            let currentIndex = body["currentIndex"] as? Int ?? -1
            DispatchQueue.main.async {
                self.onSearchResults?(matchCount, currentIndex)
            }
        } else if message.name == "visibleSection", let body = message.body as? [String: Any] {
            if let chapterIndex = body["chapterIndex"] as? Int {
                let scrollPosition = body["scrollPosition"] as? Double ?? 0
                DispatchQueue.main.async {
                    self.onVisibleSection?(chapterIndex, scrollPosition)
                }
            }
        }
    }

    func initViewportTracking(chapters: [Chapter], currentFilePath: String) {
        var anchors: [[String: Any]] = []

        for (index, chapter) in chapters.enumerated() {
            guard chapter.filePath == currentFilePath else { continue }

            if let fragment = chapter.fragment {
                anchors.append(["id": fragment, "chapterIndex": index, "isFileStart": false])
            } else {
                anchors.append(["id": "__crux_doc_start__", "chapterIndex": index, "isFileStart": true])
            }
        }

        guard !anchors.isEmpty,
              let jsonData = try? JSONSerialization.data(withJSONObject: anchors),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        webView?.evaluateJavaScript("CruxViewportTracker.init(\(jsonString));", completionHandler: nil)
    }

    func updateMarginNotes(_ notes: [MarginNoteData]) {
        guard let webView = webView,
              let jsonData = try? JSONEncoder().encode(notes),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }

        let js = "CruxMarginNotes.updateNotes(\(jsonString));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
}
