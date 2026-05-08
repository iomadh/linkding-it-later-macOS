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
    @State private var readerWebViewRef: WKWebView?
    @State private var keyboardMonitor: Any?

    // Highlights state
    @State private var highlights: [Highlight] = []
    @State private var showHighlightsList = false
    @State private var selectedText = ""
    @State private var selectedMarkdownText = ""
    @State private var showAddNoteSheet = false
    @State private var pendingNoteText = ""
    @State private var readerSnapshotTrigger = 0
    @State private var serverReaderHTML: String? = nil
    @State private var doubleClickEditingHighlight: Highlight? = nil
    @State private var doubleClickEditNoteText = ""

    private let cacheManager = OfflineCacheManager.shared

    private var isStarred: Bool {
        currentTags.contains("!star")
    }

    private var bookmarkDisplayTitle: String {
        if !bookmark.title.isEmpty { return bookmark.title }
        if let t = bookmark.websiteTitle, !t.isEmpty { return t }
        return bookmark.url
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ZStack {
                    // WebView stays in the hierarchy at all times to avoid reloading on reader mode toggle
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
                        .opacity(showReaderMode ? 0 : 1)
                    } else {
                        ContentUnavailableView("Invalid URL", systemImage: "exclamationmark.triangle")
                    }

                    if showReaderMode {
                        if let url = currentWebURL ?? displayURL {
                            ReaderModeWebView(
                                url: url,
                                isLoading: $isLoadingReader,
                                highlights: highlights,
                                serverReaderHTML: serverReaderHTML,
                                snapshotTrigger: readerSnapshotTrigger,
                                fontSize: settings.readerFontSize,
                                theme: settings.readerTheme,
                                onScrollDirectionChange: { _ in },
                                onTextSelected: { text in selectedText = text },
                                onMarkdownTextSelected: { md in selectedMarkdownText = md },
                                onSnapshotReady: { data in
                                    Task {
                                        try? await LinkdingService.shared.uploadBookmarkAsset(
                                            bookmarkId: bookmark.id,
                                            data: data,
                                            filename: "reader.html"
                                        )
                                    }
                                },
                                onWebViewCreated: { wv in readerWebViewRef = wv },
                                onDoubleClickParagraph: { paragraphText in
                                    let h = Highlight(
                                        id: UUID(),
                                        bookmarkId: bookmark.id,
                                        selectedText: paragraphText,
                                        markdownText: nil,
                                        note: nil,
                                        timestamp: Date(),
                                        bookmarkTitle: bookmarkDisplayTitle,
                                        bookmarkURL: bookmark.url,
                                        bookmarkTags: currentTags
                                    )
                                    HighlightStorage.shared.save(h)
                                    highlights = HighlightStorage.shared.load(bookmarkId: bookmark.id)
                                    uploadHighlights()
                                    ensureHighlightTag()
                                },
                                onDoubleClickHighlight: { idString in
                                    if let h = highlights.first(where: { $0.id.uuidString == idString }) {
                                        doubleClickEditNoteText = h.note ?? ""
                                        doubleClickEditingHighlight = h
                                    }
                                }
                            )
                            .id("reader-\(bookmark.id)-\(settings.readerFontSize.rawValue)-\(settings.readerTheme.rawValue)")
                        }
                    }

                    if (showReaderMode ? isLoadingReader : isLoading) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
                    }
                }

                // Selection action bar — appears below reader when text is selected
                if showReaderMode && !selectedText.isEmpty {
                    Divider()
                    HStack(spacing: 0) {
                        Button {
                            saveHighlight()
                        } label: {
                            Label("Highlight", systemImage: "highlighter")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 36)

                        Button {
                            pendingNoteText = ""
                            showAddNoteSheet = true
                        } label: {
                            Label("Add Note", systemImage: "note.text.badge.plus")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        Divider().frame(height: 36)

                        Button {
                            clearSelection()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.subheadline)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selectedText.isEmpty)

            // Right panel — highlights inspector
            if showHighlightsList {
                Divider()
                HighlightsPanelView(
                    bookmarkId: bookmark.id,
                    highlights: $highlights,
                    onChanged: uploadHighlights
                )
                .frame(width: 300)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showHighlightsList)
        .task(id: bookmark.id) {
            currentTags = bookmark.tagNames
            currentNotes = bookmark.notes
            displayURL = URL(string: bookmark.url)
            markedAsRead = !bookmark.unread
            selectedText = ""
            serverReaderHTML = nil
            showHighlightsList = false
            await loadServerAssets()
            if let tags = try? await cacheManager.fetchAllTags() {
                availableTags = tags
            }
        }
        .onChange(of: currentWebURL) { _, newURL in
            if isActive, let url = newURL {
                SettingsManager.shared.viaSourceURL = url.absoluteString
            }
        }
        .onChange(of: showReaderMode) { _, isOn in
            if isOn {
                Task { await loadServerAssets() }
            } else {
                selectedText = ""
                showHighlightsList = false
            }
        }
        .onAppear { startKeyboardMonitor() }
        .onDisappear { stopKeyboardMonitor() }
        .onChange(of: bookmark.id) { _, _ in
            stopKeyboardMonitor()
            startKeyboardMonitor()
        }
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
                .help(markedAsRead ? "Mark as unread (m)" : "Mark as read (m)")
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

                // Highlights (reader mode only)
                if showReaderMode {
                    Button {
                        showHighlightsList.toggle()
                    } label: {
                        Image(systemName: "highlighter")
                    }
                    .help("Highlights (h — toggle panel; h with selection — save highlight; a with selection — add note)")
                    .foregroundStyle(highlights.isEmpty ? Color.primary : Color.yellow)
                }

                // Reader mode
                Button {
                    showReaderMode.toggle()
                } label: {
                    Image(systemName: showReaderMode ? "doc.plaintext.fill" : "doc.plaintext")
                }
                .help(showReaderMode ? "Exit reader mode (r)" : "Enter reader mode (r)")

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
        .sheet(isPresented: $showAddNoteSheet) {
            AddHighlightNoteView(
                selectedText: selectedText,
                noteText: $pendingNoteText,
                onSave: { note in
                    saveHighlight(withNote: note.isEmpty ? nil : note)
                    showAddNoteSheet = false
                }
            )
            .frame(minWidth: 400, minHeight: 300)
        }
        .sheet(item: $doubleClickEditingHighlight) { highlight in
            EditHighlightNoteView(
                highlight: highlight,
                noteText: $doubleClickEditNoteText,
                onSave: { note in
                    HighlightStorage.shared.updateNote(id: highlight.id, bookmarkId: bookmark.id, note: note)
                    highlights = HighlightStorage.shared.load(bookmarkId: bookmark.id)
                    doubleClickEditingHighlight = nil
                    uploadHighlights()
                },
                onDelete: {
                    HighlightStorage.shared.delete(id: highlight.id, bookmarkId: bookmark.id)
                    highlights = HighlightStorage.shared.load(bookmarkId: bookmark.id)
                    doubleClickEditingHighlight = nil
                    uploadHighlights()
                }
            )
            .frame(minWidth: 400, minHeight: 300)
        }
    }

    // MARK: - Highlights

    @MainActor
    private func loadServerAssets() async {
        serverReaderHTML = nil
        if let data = try? await LinkdingService.shared.downloadAsset(bookmarkId: bookmark.id, filename: "highlights.md") {
            highlights = HighlightStorage.shared.overwriteFromMarkdown(
                data,
                bookmarkId: bookmark.id,
                bookmarkTitle: bookmarkDisplayTitle,
                bookmarkURL: bookmark.url
            )
        } else {
            highlights = HighlightStorage.shared.load(bookmarkId: bookmark.id)
        }
        if let data = try? await LinkdingService.shared.downloadAsset(bookmarkId: bookmark.id, filename: "reader.html"),
           let html = String(data: data, encoding: .utf8) {
            serverReaderHTML = html
        }
    }

    private func saveHighlight(withNote note: String? = nil) {
        let h = Highlight(
            id: UUID(),
            bookmarkId: bookmark.id,
            selectedText: selectedText,
            markdownText: selectedMarkdownText == selectedText ? nil : selectedMarkdownText,
            note: note,
            timestamp: Date(),
            bookmarkTitle: bookmarkDisplayTitle,
            bookmarkURL: bookmark.url,
            bookmarkTags: currentTags
        )
        HighlightStorage.shared.save(h)
        highlights = HighlightStorage.shared.load(bookmarkId: bookmark.id)
        selectedText = ""
        selectedMarkdownText = ""
        uploadHighlights()
        ensureHighlightTag()
    }

    private func clearSelection() {
        selectedText = ""
        selectedMarkdownText = ""
    }

    private func uploadHighlights() {
        guard let data = HighlightStorage.shared.markdownData(bookmarkId: bookmark.id) else { return }
        readerSnapshotTrigger += 1
        Task {
            try? await LinkdingService.shared.uploadBookmarkAsset(
                bookmarkId: bookmark.id,
                data: data,
                filename: "highlights.md"
            )
        }
    }

    private func ensureHighlightTag() {
        guard !currentTags.contains(".highlight") else { return }
        updateTags(currentTags + [".highlight"])
    }

    // MARK: - Bookmark actions

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
            if HighlightStorage.shared.markdownData(bookmarkId: bookmark.id) != nil {
                HighlightStorage.shared.updateTags(newTags, bookmarkId: bookmark.id)
                highlights = HighlightStorage.shared.load(bookmarkId: bookmark.id)
                uploadHighlights()
            }
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
            if let fr = NSApp.keyWindow?.firstResponder, fr is NSTextView {
                return event
            }
            if isEditingTags || isEditingNotes || showAddNoteSheet { return event }
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

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard let chars = event.charactersIgnoringModifiers else { return event }

        switch chars {
        case "m", "u":
            toggleReadStatus()
            return nil

        case "r":
            showReaderMode.toggle()
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

        case "h":
            if showReaderMode {
                if !selectedText.isEmpty {
                    saveHighlight()
                } else {
                    showHighlightsList.toggle()
                }
            }
            return nil

        case "a":
            if showReaderMode && !selectedText.isEmpty {
                pendingNoteText = ""
                showAddNoteSheet = true
            }
            return nil

        case "b":
            if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
            return nil

        case "\r", "\n":
            if let url = URL(string: bookmark.url) { NSWorkspace.shared.open(url) }
            return nil

        case " ":
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
        let wv = showReaderMode ? readerWebViewRef : webViewRef
        guard let wv else {
            navigateNext()
            return
        }
        wv.evaluateJavaScript(
            "(function(){ var e = document.documentElement; return e.scrollTop + e.clientHeight >= e.scrollHeight - 50; })()"
        ) { result, _ in
            DispatchQueue.main.async {
                if let atBottom = result as? Bool, atBottom {
                    self.navigateNext()
                } else {
                    wv.evaluateJavaScript("window.scrollBy(0, Math.round(window.innerHeight * 0.85))", completionHandler: nil)
                }
            }
        }
    }

    private func navigateNext() {
        NotificationCenter.default.post(name: .navigateNextUnread, object: nil)
    }
}

// MARK: - Add Highlight Note View

private struct AddHighlightNoteView: View {
    let selectedText: String
    @Binding var noteText: String
    let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Note")
                .font(.headline)

            Text(selectedText)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.25))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.6), lineWidth: 1))

            TextEditor(text: $noteText)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { onSave(noteText) }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}

// MARK: - Reader Mode WebView (macOS)

struct ReaderModeWebView: NSViewRepresentable {
    let url: URL
    @Binding var isLoading: Bool
    let highlights: [Highlight]
    let serverReaderHTML: String?
    let snapshotTrigger: Int
    let fontSize: ReaderFontSize
    let theme: ReaderTheme
    let onScrollDirectionChange: (Bool) -> Void
    var onTextSelected: ((String) -> Void)? = nil
    var onMarkdownTextSelected: ((String) -> Void)? = nil
    var onSnapshotReady: ((Data) -> Void)? = nil
    var onWebViewCreated: ((WKWebView) -> Void)? = nil
    var onDoubleClickParagraph: ((String) -> Void)? = nil
    var onDoubleClickHighlight: ((String) -> Void)? = nil

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "scrollHandler")
        contentController.add(context.coordinator, name: "selectionHandler")
        contentController.add(context.coordinator, name: "doubleClickHandler")
        config.userContentController = contentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        onWebViewCreated?(webView)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.fontSize = fontSize
        context.coordinator.theme = theme
        context.coordinator.highlights = highlights
        context.coordinator.onTextSelected = onTextSelected
        context.coordinator.onMarkdownTextSelected = onMarkdownTextSelected
        context.coordinator.onSnapshotReady = onSnapshotReady
        context.coordinator.onDoubleClickParagraph = onDoubleClickParagraph
        context.coordinator.onDoubleClickHighlight = onDoubleClickHighlight

        let serverHTMLJustArrived = context.coordinator.serverReaderHTML == nil && serverReaderHTML != nil
        context.coordinator.serverReaderHTML = serverReaderHTML

        if snapshotTrigger != context.coordinator.snapshotTrigger {
            context.coordinator.snapshotTrigger = snapshotTrigger
            context.coordinator.pendingSnapshot = true
        }

        if serverHTMLJustArrived && !context.coordinator.isLoadingReaderHTML {
            context.coordinator.requestedURL = nil
        }

        if !context.coordinator.isLoadingReaderHTML && context.coordinator.requestedURL != url {
            context.coordinator.requestedURL = url
            webView.load(URLRequest(url: url))
        } else {
            context.coordinator.applyReaderStyling(webView)
            context.coordinator.applyHighlights(webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self, fontSize: fontSize, theme: theme)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: ReaderModeWebView
        var fontSize: ReaderFontSize
        var theme: ReaderTheme
        var highlights: [Highlight] = []
        var onTextSelected: ((String) -> Void)?
        var onMarkdownTextSelected: ((String) -> Void)?
        var onSnapshotReady: ((Data) -> Void)?
        var onDoubleClickParagraph: ((String) -> Void)?
        var onDoubleClickHighlight: ((String) -> Void)?
        var serverReaderHTML: String? = nil
        var snapshotTrigger: Int = -1
        var pendingSnapshot = false
        var requestedURL: URL? = nil
        var isLoadingReaderHTML = false
        private var hasExtractedContent = false

        init(_ parent: ReaderModeWebView, fontSize: ReaderFontSize, theme: ReaderTheme) {
            self.parent = parent
            self.fontSize = fontSize
            self.theme = theme
            self.highlights = parent.highlights
            self.onTextSelected = parent.onTextSelected
            self.onMarkdownTextSelected = parent.onMarkdownTextSelected
            self.onSnapshotReady = parent.onSnapshotReady
            self.onDoubleClickParagraph = parent.onDoubleClickParagraph
            self.onDoubleClickHighlight = parent.onDoubleClickHighlight
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "scrollHandler", let body = message.body as? [String: Any] {
                if let scrollingDown = body["scrollingDown"] as? Bool {
                    DispatchQueue.main.async {
                        self.parent.onScrollDirectionChange(scrollingDown)
                    }
                }
            } else if message.name == "selectionHandler", let body = message.body as? [String: Any] {
                let text = (body["text"] as? String) ?? ""
                let md = (body["markdownText"] as? String) ?? text
                DispatchQueue.main.async {
                    self.onTextSelected?(text)
                    self.onMarkdownTextSelected?(md)
                }
            } else if message.name == "doubleClickHandler", let body = message.body as? [String: Any] {
                let type = body["type"] as? String
                if type == "existing", let id = body["highlightId"] as? String {
                    DispatchQueue.main.async { self.onDoubleClickHighlight?(id) }
                } else if type == "new", let text = body["paragraphText"] as? String, !text.isEmpty {
                    DispatchQueue.main.async { self.onDoubleClickParagraph?(text) }
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            hasExtractedContent = false
            if !isLoadingReaderHTML {
                DispatchQueue.main.async { self.parent.isLoading = true }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if isLoadingReaderHTML {
                isLoadingReaderHTML = false
                hasExtractedContent = true
                injectInteractionScripts(webView)
                applyHighlights(webView)
                DispatchQueue.main.async { self.parent.isLoading = false }
                return
            }

            // If the server already has a reader.html, use it directly — no Readability needed
            if let serverHTML = serverReaderHTML {
                isLoadingReaderHTML = true
                let baseURL = parent.url
                DispatchQueue.main.async {
                    webView.loadHTMLString(serverHTML, baseURL: baseURL)
                }
                return
            }

            // No server snapshot yet — run Readability and upload the result immediately
            pendingSnapshot = true

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
                let baseURL = self.parent.url
                self.isLoadingReaderHTML = true
                DispatchQueue.main.async {
                    webView.loadHTMLString(readerHTML, baseURL: baseURL)
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

        func applyHighlights(_ webView: WKWebView) {
            guard hasExtractedContent else { return }

            let shouldSnapshot = pendingSnapshot
            pendingSnapshot = false

            guard !highlights.isEmpty else {
                if shouldSnapshot { captureSnapshot(webView) }
                return
            }

            let highlightsData: [[String: Any]] = highlights.map { h in
                ["id": h.id.uuidString, "selectedText": h.selectedText, "hasNote": h.note != nil && !h.note!.isEmpty]
            }

            guard let jsonData = try? JSONSerialization.data(withJSONObject: highlightsData),
                  let jsonString = String(data: jsonData, encoding: .utf8) else { return }

            let script = """
            (function() {
                var highlights = \(jsonString);

                document.querySelectorAll('mark[data-highlight-id]').forEach(function(mark) {
                    var parent = mark.parentNode;
                    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
                    parent.removeChild(mark);
                });
                document.querySelectorAll('span[data-note-indicator]').forEach(function(el) { el.remove(); });
                document.body.normalize();

                highlights.forEach(function(h) {
                    var textNodes = [];
                    var totalText = '';
                    var walker = document.createTreeWalker(
                        document.body,
                        NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT,
                        { acceptNode: function(n) {
                            if (n.nodeType === 1) {
                                var t = n.tagName;
                                if (t === 'SCRIPT' || t === 'STYLE' || t === 'MARK') return NodeFilter.FILTER_REJECT;
                                return NodeFilter.FILTER_SKIP;
                            }
                            return NodeFilter.FILTER_ACCEPT;
                        }}
                    );
                    var node;
                    while ((node = walker.nextNode()) !== null) {
                        textNodes.push({ node: node, start: totalText.length });
                        totalText += node.textContent;
                    }

                    var matchIdx = totalText.indexOf(h.selectedText);
                    if (matchIdx === -1) return;
                    var matchEnd = matchIdx + h.selectedText.length;

                    for (var i = textNodes.length - 1; i >= 0; i--) {
                        var tn = textNodes[i];
                        var nodeEnd = tn.start + tn.node.textContent.length;
                        if (nodeEnd <= matchIdx || tn.start >= matchEnd) continue;
                        var ls = Math.max(matchIdx, tn.start) - tn.start;
                        var le = Math.min(matchEnd, nodeEnd) - tn.start;
                        var txt = tn.node.textContent;
                        var frag = document.createDocumentFragment();
                        if (ls > 0) frag.appendChild(document.createTextNode(txt.substring(0, ls)));
                        var mark = document.createElement('mark');
                        mark.style.cssText = 'background-color: rgba(255, 220, 0, 0.45); border-radius: 2px; padding: 1px 0;';
                        mark.dataset.highlightId = h.id;
                        mark.textContent = txt.substring(ls, le);
                        frag.appendChild(mark);
                        if (le < txt.length) frag.appendChild(document.createTextNode(txt.substring(le)));
                        tn.node.parentNode.replaceChild(frag, tn.node);
                    }

                    // Add tiny note indicator dot after the last mark for this highlight
                    if (h.hasNote) {
                        var marks = document.querySelectorAll('mark[data-highlight-id="' + h.id + '"]');
                        if (marks.length > 0) {
                            var dot = document.createElement('span');
                            dot.dataset.noteIndicator = h.id;
                            dot.style.cssText = 'display:inline-block;width:6px;height:6px;background:#f5c000;border-radius:50%;vertical-align:super;font-size:0;margin-left:2px;';
                            var lastMark = marks[marks.length - 1];
                            lastMark.parentNode.insertBefore(dot, lastMark.nextSibling);
                        }
                    }
                });
            })();
            """

            webView.evaluateJavaScript(script) { [weak self] _, _ in
                guard let self, shouldSnapshot else { return }
                self.captureSnapshot(webView)
            }
        }

        private func injectInteractionScripts(_ webView: WKWebView) {
            let js = """
            (function() {
                if (window._linkdingScriptsLoaded) return;
                window._linkdingScriptsLoaded = true;

                var lastScrollY = window.scrollY;
                var ticking = false;
                var lastDirection = null;
                var scrollThreshold = 10;
                window.addEventListener('scroll', function() {
                    if (!ticking) {
                        window.requestAnimationFrame(function() {
                            var cur = window.scrollY;
                            var diff = cur - lastScrollY;
                            if (Math.abs(diff) > scrollThreshold) {
                                var down = diff > 0;
                                var atBottom = (window.innerHeight + cur) >= document.body.scrollHeight - 10;
                                if (!atBottom && down !== lastDirection) {
                                    lastDirection = down;
                                    window.webkit.messageHandlers.scrollHandler.postMessage({ scrollingDown: down });
                                }
                                lastScrollY = cur;
                            }
                            ticking = false;
                        });
                        ticking = true;
                    }
                });

                function resolveURL(href) {
                    var a = document.createElement('a');
                    a.href = href;
                    return a.href;
                }
                function selectionToMarkdown(sel) {
                    if (!sel || sel.rangeCount === 0) return '';
                    var frag = sel.getRangeAt(0).cloneContents();
                    function walk(node) {
                        if (node.nodeType === 3) return node.textContent;
                        if (node.nodeType === 1 && node.tagName === 'A') {
                            var raw = node.getAttribute('href') || '';
                            var href = raw ? resolveURL(raw) : '';
                            var text = Array.from(node.childNodes).map(walk).join('');
                            if (href && !href.startsWith('#') && !href.startsWith('javascript:') && text.trim()) {
                                return '[' + text.trim() + '](' + href + ')';
                            }
                            return text;
                        }
                        if (node.childNodes) return Array.from(node.childNodes).map(walk).join('');
                        return '';
                    }
                    return walk(frag).replace(/[ \\t\\r\\n]+/g, ' ').trim();
                }
                function reportSelection() {
                    var sel = window.getSelection();
                    var text = sel ? sel.toString().trim() : '';
                    var md = selectionToMarkdown(sel) || text;
                    window.webkit.messageHandlers.selectionHandler.postMessage({ text: text, markdownText: md });
                }
                document.addEventListener('pointerup', function() { setTimeout(reportSelection, 100); });
                document.addEventListener('mouseup',   function() { setTimeout(reportSelection, 100); });
                var selTimer = null;
                document.addEventListener('selectionchange', function() {
                    clearTimeout(selTimer);
                    selTimer = setTimeout(reportSelection, 200);
                });

                document.addEventListener('dblclick', function(e) {
                    var el = e.target;

                    // Check if click landed on an existing highlight mark
                    var markEl = (el.closest ? el.closest('mark[data-highlight-id]') : null)
                                 || (el.tagName === 'MARK' && el.dataset && el.dataset.highlightId ? el : null);
                    if (markEl && markEl.dataset.highlightId) {
                        if (window.getSelection) window.getSelection().removeAllRanges();
                        window.webkit.messageHandlers.doubleClickHandler.postMessage({ type: 'existing', highlightId: markEl.dataset.highlightId });
                        return;
                    }

                    // Walk up to the nearest block element
                    var blockTags = ['P', 'LI', 'BLOCKQUOTE', 'H1', 'H2', 'H3', 'H4', 'H5', 'H6', 'TD', 'TH'];
                    var block = el;
                    while (block && block !== document.body) {
                        if (blockTags.indexOf(block.tagName) !== -1) break;
                        block = block.parentElement;
                    }
                    if (!block || block === document.body) return;

                    // If the block already contains a highlight, open edit for the first mark in it
                    var existingMark = block.querySelector('mark[data-highlight-id]');
                    if (existingMark && existingMark.dataset.highlightId) {
                        if (window.getSelection) window.getSelection().removeAllRanges();
                        window.webkit.messageHandlers.doubleClickHandler.postMessage({ type: 'existing', highlightId: existingMark.dataset.highlightId });
                        return;
                    }

                    var text = (block.innerText || '').replace(/\\s+/g, ' ').trim();
                    if (!text) return;

                    if (window.getSelection) window.getSelection().removeAllRanges();
                    window.webkit.messageHandlers.doubleClickHandler.postMessage({ type: 'new', paragraphText: text });
                });
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }

        private func captureSnapshot(_ webView: WKWebView) {
            webView.evaluateJavaScript("document.documentElement.outerHTML") { [weak self] result, _ in
                guard let html = result as? String,
                      let data = html.data(using: .utf8) else { return }
                self?.onSnapshotReady?(data)
            }
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

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            isLoadingReaderHTML = false
            DispatchQueue.main.async { self.parent.isLoading = false }
        }
    }
}
