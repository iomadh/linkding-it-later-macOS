//
//  NotesEditingView.swift
//  Linkding It Later
//

import SwiftUI
import WebKit
import AppKit

struct NotesEditingView: View {
    let initialNotes: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var notes: String
    @State private var isEditing: Bool

    init(initialNotes: String, onSave: @escaping (String) -> Void) {
        self.initialNotes = initialNotes
        self.onSave = onSave
        _notes = State(initialValue: initialNotes)
        _isEditing = State(initialValue: initialNotes.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEditing {
                    TextEditor(text: $notes)
                        .padding()
                        .font(.body)
                } else {
                    MarkdownWebView(markdown: notes)
                }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isEditing ? "Cancel" : "Done") {
                        if isEditing && notes != initialNotes {
                            notes = initialNotes
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isEditing {
                        Button("Save") {
                            onSave(notes)
                            isEditing = false
                        }
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Markdown WebView (macOS)

struct MarkdownWebView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(from: markdown)
        webView.loadHTMLString(html, baseURL: nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    private func generateHTML(from markdown: String) -> String {
        let escapedMarkdown = markdown
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")

        let markedJS: String
        if let path = Bundle.main.path(forResource: "marked.min", ofType: "js"),
           let content = try? String(contentsOfFile: path) {
            markedJS = content
        } else {
            markedJS = ""
        }

        return """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <script>\(markedJS)</script>
        <style>
            :root { color-scheme: light dark; }
            body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; font-size: 14px;
                   line-height: 1.5; padding: 16px; margin: 0; background: transparent; color: var(--text-color); }
            @media (prefers-color-scheme: dark) { :root { --text-color: #fff; --code-bg: #2d2d2d; --quote-border: #555; } }
            @media (prefers-color-scheme: light) { :root { --text-color: #000; --code-bg: #f4f4f4; --quote-border: #ddd; } }
            a { color: #007AFF; }
            pre, code { background: var(--code-bg); border-radius: 4px; padding: 2px 6px;
                        font-family: ui-monospace, Menlo, monospace; font-size: 13px; }
            pre { padding: 12px; overflow-x: auto; }
            pre code { padding: 0; background: none; }
            blockquote { margin: 0; padding-left: 16px; border-left: 4px solid var(--quote-border); color: gray; }
            h1, h2, h3, h4, h5, h6 { margin-top: 1em; margin-bottom: 0.5em; }
            h1 { font-size: 1.5em; } h2 { font-size: 1.3em; } h3 { font-size: 1.1em; }
            p { margin: 0.5em 0; }
            ul, ol { padding-left: 24px; }
        </style></head>
        <body>
        <div id="content"></div>
        <script>document.getElementById('content').innerHTML = marked.parse(`\(escapedMarkdown)`);</script>
        </body></html>
        """
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
