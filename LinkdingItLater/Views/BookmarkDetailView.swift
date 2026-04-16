//
//  BookmarkDetailView.swift
//  Linkding It Later
//

import SwiftUI
import WebKit

struct BookmarkDetailView: View {
    let bookmark: Bookmark
    let isActive: Bool
    let onMarkAsRead: () -> Void
    let onTagsUpdated: ([String]) -> Void
    let onNotesUpdated: (String) -> Void

    @State private var isLoading = true
    @State private var displayURL: URL?
    @State private var isMarkingRead = false
    @State private var markedAsRead = false
    @State private var isEditingTags = false
    @State private var isEditingNotes = false
    @State private var availableTags: [String] = []
    @State private var currentTags: [String] = []
    @State private var currentNotes: String = ""
    @State private var isTogglingStarred = false
    @State private var currentWebURL: URL?
    @State private var showReaderMode = false
    @State private var isLoadingReader = false
    @ObservedObject private var settings = SettingsManager.shared
    @State private var webViewRef: WKWebView?
    @State private var keyboardMonitor: Any?

    private let cacheManager = OfflineCacheManager.shared

    private var isStarred: Bool {
        currentTags.contains("!star")
    }

    var body: some View {
        ZStack {
            if showReaderMode {
                if let url = currentWebURL ?? displayURL {
                    ReaderModeWebView(
                        url: url,
                        isLoading: $isLoadingReader,
                        fontSize: settings.readerFontSize,
                        theme: settings.readerTheme,
                        onScrollDirectionChange: { _ in }
                    )
                    .id("reader-\(bookmark.id)-\(settings.readerFontSize.rawValue)-\(settings.readerTheme.rawValue)")
                }
            } else {
                if let url = displayURL {
                    WebView(
                        url: url,
                        isLoading: $isLoading,
                        fallbackURL: URL(string: bookmark.url),
                        currentURL: $currentWebURL,
                        onLinkTapped: { tappedURL in
                            NSWorkspace.shared.open(tappedURL)
                        },
                        onWebViewCreated: { wv in
                            webViewRef = wv
                        }
                    )
                    .id(bookmark.id)
                } else {
                    ContentUnavailableView("Invalid URL", systemImage: "exclamationmark.triangle")
                }
            }

            if (showReaderMode ? isLoadingReader : isLoading) {
                ProgressView()
                    .scaleEffect(1.5)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
            }
        }
        .task(id: bookmark.id) {
            currentTags = bookmark.tagNames
            currentNotes = bookmark.notes
            displayURL = URL(string: bookmark.url)
            if let tags = try? await cacheManager.fetchAllTags() {
                availableTags = tags
            }
        }
        .onChange(of: currentWebURL) { _, newURL in
            if isActive, let url = newURL {
                SettingsManager.shared.viaSourceURL = url.absoluteString
            }
        }
        .onAppear { startKeyboardMonitor() }
        .onDisappear { stopKeyboardMonitor() }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Mark as read
                Button {
                    toggleReadStatus()
                } label: {
                    if isMarkingRead {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: markedAsRead ? "checkmark.circle.fill" : "circle")
                    }
                }
                .help(markedAsRead ? "Mark as unread" : "Mark as read")
                .disabled(isMarkingRead)
                .keyboardShortcut(.return, modifiers: .command)

                // Star
                Button {
                    toggleStar()
                } label: {
                    if isTogglingStarred {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: isStarred ? "star.fill" : "star")
                    }
                }
                .help(isStarred ? "Unstar" : "Star")
                .disabled(isTogglingStarred)
                .keyboardShortcut("s", modifiers: [.command, .shift])

                // Tags
                Button {
                    isEditingTags = true
                } label: {
                    Image(systemName: "tag")
                }
                .help("Edit tags")

                // Notes
                Button {
                    isEditingNotes = true
                } label: {
                    Image(systemName: currentNotes.isEmpty ? "note.text" : "note.text.badge.plus")
                }
                .help("Edit notes")

                // Share
                if let shareURL = currentWebURL ?? URL(string: bookmark.url) {
                    ShareLink(item: shareURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Share")
                }

                Divider()

                // Reader mode
                Button {
                    showReaderMode.toggle()
                } label: {
                    Image(systemName: showReaderMode ? "doc.plaintext.fill" : "doc.plaintext")
                }
                .help(showReaderMode ? "Exit reader mode" : "Enter reader mode")
                .keyboardShortcut("r", modifiers: [.command, .shift])

                // Open in browser
                if let url = URL(string: bookmark.url) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "safari")
                    }
                    .help("Open in browser")
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                }
            }
        }
        .sheet(isPresented: $isEditingTags) {
            TagEditingView(
                bookmarkId: bookmark.id,
                initialTags: currentTags,
                availableTags: availableTags,
                onSave: { newTags in
                    updateTags(newTags)
                }
            )
            .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(isPresented: $isEditingNotes) {
            NotesEditingView(
                initialNotes: currentNotes,
                onSave: { newNotes in
                    updateNotes(newNotes)
                }
            )
            .frame(minWidth: 500, minHeight: 400)
        }
    }

    private func toggleReadStatus() {
        isMarkingRead = true
        let newUnreadStatus = markedAsRead

        Task { @MainActor in
            try? await cacheManager.setUnreadStatus(bookmarkId: bookmark.id, unread: newUnreadStatus)
            markedAsRead = !markedAsRead
            if markedAsRead {
                onMarkAsRead()
            }
            isMarkingRead = false
        }
    }

    private func toggleStar() {
        isTogglingStarred = true
        var newTags = currentTags

        if isStarred {
            newTags.removeAll { $0 == "!star" }
        } else {
            newTags.append("!star")
        }

        Task { @MainActor in
            try? await cacheManager.updateBookmarkTags(bookmarkId: bookmark.id, tags: newTags)
            currentTags = newTags
            onTagsUpdated(newTags)
            isTogglingStarred = false
        }
    }

    private func updateTags(_ newTags: [String]) {
        Task { @MainActor in
            try? await cacheManager.updateBookmarkTags(bookmarkId: bookmark.id, tags: newTags)
            currentTags = newTags
            onTagsUpdated(newTags)
        }
    }

    private func updateNotes(_ newNotes: String) {
        Task { @MainActor in
            try? await cacheManager.updateBookmarkNotes(bookmarkId: bookmark.id, notes: newNotes)
            currentNotes = newNotes
            onNotesUpdated(newNotes)
        }
    }

    // MARK: - Keyboard Shortcuts

    private func startKeyboardMonitor() {
        keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Don't intercept when typing in a text field / text view
            if let fr = NSApp.keyWindow?.firstResponder, fr is NSTextView {
                return event
            }
            // Don't intercept when a sheet is presented
            if isEditingTags || isEditingNotes { return event }
            // Only plain key presses (no Cmd/Opt/Ctrl)
            guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else {
                return event
            }
            return handleKey(event)
        }
    }

    private func stopKeyboardMonitor() {
        if let m = keyboardMonitor { NSEvent.removeMonitor(m) }
        keyboardMonitor = nil
    }

    /// Returns nil if the event was consumed, or the original event to pass through.
    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let chars = event.charactersIgnoringModifiers else { return event }

        switch chars {
        case "r", "u":
            toggleReadStatus()
            return nil

        case "s":
            toggleStar()
            return nil

        case "t":
            isEditingTags = true
            return nil

        case "e":
            isEditingNotes = true
            return nil

        case "b":
            if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
            return nil

        case "\r", "\n":   // Return / Enter
            if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
            return nil

        case " ":   // Space — scroll page, or navigate next if at bottom
            scrollOrNavigateNext()
            return nil

        case "n", "+":
            navigateNext()
            return nil

        default:
            return event
        }
    }

    private func scrollOrNavigateNext() {
        guard let wv = webViewRef, !showReaderMode else {
            navigateNext()
            return
        }
        // Check if already scrolled to the bottom
        wv.evaluateJavaScript(
            "(function(){ var e = document.documentElement; return e.scrollTop + e.clientHeight >= e.scrollHeight - 50; })()"
        ) { result, _ in
            DispatchQueue.main.async {
                if let atBottom = result as? Bool, atBottom {
                    self.navigateNext()
                } else {
                    // Scroll down by 85% of visible height
                    wv.evaluateJavaScript("window.scrollBy(0, Math.round(window.innerHeight * 0.85))", completionHandler: nil)
                }
            }
        }
    }

    private func navigateNext() {
        NotificationCenter.default.post(name: .navigateNextUnread, object: nil)
    }
}

// MARK: - Reader Mode WebView (macOS)

struct ReaderModeWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let fontSize: ReaderFontSize
    let theme: ReaderTheme
    let onScrollDirectionChange: (Bool) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scrollHandler")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.fontSize = fontSize
        context.coordinator.theme = theme

        if webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        } else {
            context.coordinator.applyReaderStyling(webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, fontSize: fontSize, theme: theme)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderModeWebView
        var fontSize: ReaderFontSize
        var theme: ReaderTheme
        private var hasExtractedContent = false

        init(_ parent: ReaderModeWebView, fontSize: ReaderFontSize, theme: ReaderTheme) {
            self.parent = parent
            self.fontSize = fontSize
            self.theme = theme
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "scrollHandler", let body = message.body as? [String: Any] {
                if let scrollingDown = body["scrollingDown"] as? Bool {
                    DispatchQueue.main.async {
                        self.parent.onScrollDirectionChange(scrollingDown)
                    }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            hasExtractedContent = false
            DispatchQueue.main.async { self.parent.isLoading = true }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let path = Bundle.main.path(forResource: "Readability", ofType: "js"),
                  let readabilityJS = try? String(contentsOfFile: path, encoding: .utf8) else {
                DispatchQueue.main.async { self.parent.isLoading = false }
                return
            }

            let extractionScript = """
            \(readabilityJS)
            (function() {
                var documentClone = document.cloneNode(true);
                var article = new Readability(documentClone).parse();
                if (!article) {
                    return { title: document.title || '', content: '<p>Could not extract article content.</p>', byline: '' };
                }
                return { title: article.title || '', content: article.content || '', byline: article.byline || '' };
            })();
            """

            webView.evaluateJavaScript(extractionScript) { [weak self] result, _ in
                guard let self = self else { return }
                var title = ""
                var content = "<p>Could not extract article content.</p>"
                var byline = ""
                if let dict = result as? [String: Any] {
                    title = dict["title"] as? String ?? ""
                    content = dict["content"] as? String ?? content
                    byline = dict["byline"] as? String ?? ""
                }
                let readerHTML = self.buildReaderHTML(title: title, byline: byline, content: content)
                let loadHTMLScript = "document.open(); document.write(\(self.escapeForJS(readerHTML))); document.close();"
                webView.evaluateJavaScript(loadHTMLScript) { _, _ in
                    self.hasExtractedContent = true
                    DispatchQueue.main.async { self.parent.isLoading = false }
                }
            }
        }

        func applyReaderStyling(_ webView: WKWebView) {
            guard hasExtractedContent else { return }
            let colors = theme.colors
            let styleScript = """
            (function() {
                document.documentElement.style.setProperty('--bg', '\(colors.bg)');
                document.documentElement.style.setProperty('--text', '\(colors.text)');
                document.documentElement.style.setProperty('--link', '\(colors.link)');
                document.body.style.fontSize = '\(fontSize.pixels)px';
            })();
            """
            webView.evaluateJavaScript(styleScript, completionHandler: nil)
        }

        private func buildReaderHTML(title: String, byline: String, content: String) -> String {
            let colors = theme.colors
            let bylineHTML = byline.isEmpty ? "" : "<p class=\"byline\">\(escapeHTML(byline))</p>"
            return """
            <!DOCTYPE html><html><head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
                :root { --bg: \(colors.bg); --text: \(colors.text); --link: \(colors.link); }
                body { font-family: -apple-system, Georgia, serif; font-size: \(fontSize.pixels)px; line-height: 1.6;
                       max-width: 700px; margin: 0 auto; padding: 20px; background: var(--bg); color: var(--text); }
                h1 { font-size: 1.5em; line-height: 1.3; margin-bottom: 0.5em; }
                .byline { color: var(--text); opacity: 0.7; font-style: italic; margin-bottom: 1.5em; }
                a { color: var(--link); }
                img { max-width: 100%; height: auto; }
                figure { margin: 1em 0; }
                figcaption { font-size: 0.9em; color: var(--text); opacity: 0.7; margin-top: 0.5em; }
                pre, code { background: rgba(128,128,128,0.1); padding: 2px 6px; border-radius: 4px; font-size: 0.9em; }
                pre { padding: 12px; overflow-x: auto; }
                pre code { padding: 0; background: none; }
                blockquote { margin: 1em 0; padding-left: 1em; border-left: 3px solid var(--link); opacity: 0.9; }
            </style></head>
            <body><h1>\(escapeHTML(title))</h1>\(bylineHTML)\(content)</body></html>
            """
        }

        private func escapeHTML(_ string: String) -> String {
            string.replacingOccurrences(of: "&", with: "&amp;")
                  .replacingOccurrences(of: "<", with: "&lt;")
                  .replacingOccurrences(of: ">", with: "&gt;")
                  .replacingOccurrences(of: "\"", with: "&quot;")
                  .replacingOccurrences(of: "'", with: "&#39;")
        }

        private func escapeForJS(_ string: String) -> String {
            let escaped = string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "`", with: "\\`")
                .replacingOccurrences(of: "$", with: "\\$")
            return "`\(escaped)`"
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
