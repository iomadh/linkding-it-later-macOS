//
//  HighlightStorage.swift
//  Linkding It Later
//

import Foundation

final class HighlightStorage {
    static let shared = HighlightStorage()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let queue = DispatchQueue(label: "com.dellah.linkdingitlater.highlightStorage", qos: .userInitiated)

    private var highlightsDirectory: URL? {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Highlights", isDirectory: true)
    }

    private init() {
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        createDirectoryIfNeeded()
    }

    private func createDirectoryIfNeeded() {
        guard let dir = highlightsDirectory else { return }
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func jsonURL(for bookmarkId: Int) -> URL? {
        highlightsDirectory?.appendingPathComponent("\(bookmarkId).json")
    }

    private func markdownURL(for bookmarkId: Int) -> URL? {
        highlightsDirectory?.appendingPathComponent("\(bookmarkId).md")
    }

    func save(_ highlight: Highlight) {
        queue.sync {
            var highlights = _load(bookmarkId: highlight.bookmarkId)
            highlights.append(highlight)
            _save(highlights, bookmarkId: highlight.bookmarkId)
        }
    }

    func load(bookmarkId: Int) -> [Highlight] {
        queue.sync {
            _load(bookmarkId: bookmarkId)
        }
    }

    func delete(id: UUID, bookmarkId: Int) {
        queue.sync {
            var highlights = _load(bookmarkId: bookmarkId)
            highlights.removeAll { $0.id == id }
            _save(highlights, bookmarkId: bookmarkId)
        }
    }

    func markdownData(bookmarkId: Int) -> Data? {
        queue.sync {
            guard let url = markdownURL(for: bookmarkId),
                  fileManager.fileExists(atPath: url.path) else { return nil }
            return try? Data(contentsOf: url)
        }
    }

    /// Parses highlights.md from the server and replaces local storage with it.
    /// Server is the source of truth; local cache is kept in sync for uploads.
    @discardableResult
    func overwriteFromMarkdown(_ data: Data, bookmarkId: Int, bookmarkTitle: String, bookmarkURL: String) -> [Highlight] {
        queue.sync {
            let parsed = parseMarkdown(data, bookmarkId: bookmarkId, bookmarkTitle: bookmarkTitle, bookmarkURL: bookmarkURL)
            _save(parsed, bookmarkId: bookmarkId)
            return parsed
        }
    }

    func parseMarkdown(_ data: Data, bookmarkId: Int, bookmarkTitle: String, bookmarkURL: String) -> [Highlight] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var highlights: [Highlight] = []
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")

        // Parse tags from frontmatter (between first two --- markers)
        var parsedTags: [String] = []
        var frontmatterEnd = 0
        if lines.first == "---" {
            var inTags = false
            for j in 1..<lines.count {
                let l = lines[j]
                if l == "---" { frontmatterEnd = j; break }
                if l == "tags:" { inTags = true; continue }
                if inTags {
                    if l.hasPrefix("  - ") {
                        parsedTags.append(String(l.dropFirst(4)))
                    } else {
                        inTags = false
                    }
                }
            }
        }

        var i = frontmatterEnd
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("> ") && !line.hasPrefix("> > ") && !line.hasPrefix("> [!") && line.count > 2 {
                let rawText = String(line.dropFirst(2))
                let plainText = stripMarkdownLinks(rawText)
                let markdownText = rawText == plainText ? nil : rawText
                var note: String? = nil
                // note may follow directly or after a blank "> " separator line
                let noteStart = (i + 1 < lines.count && (lines[i + 1] == ">" || lines[i + 1] == "> ")) ? i + 2 : i + 1
                if noteStart < lines.count && lines[noteStart].hasPrefix("> > ") {
                    var noteLines: [String] = []
                    var j = noteStart
                    while j < lines.count && lines[j].hasPrefix("> > ") {
                        noteLines.append(String(lines[j].dropFirst(4)))
                        j += 1
                    }
                    while noteLines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { noteLines.removeLast() }
                    let noteText = noteLines.joined(separator: "\n")
                    note = noteText.isEmpty ? nil : noteText
                    i = j - 1
                }
                if !plainText.isEmpty {
                    highlights.append(Highlight(
                        id: UUID(),
                        bookmarkId: bookmarkId,
                        selectedText: plainText,
                        markdownText: markdownText,
                        note: note,
                        timestamp: Date(),
                        bookmarkTitle: bookmarkTitle,
                        bookmarkURL: bookmarkURL,
                        bookmarkTags: parsedTags.isEmpty ? nil : parsedTags
                    ))
                }
            }
            i += 1
        }
        return highlights
    }

    func updateTags(_ tags: [String], bookmarkId: Int) {
        queue.sync {
            var highlights = _load(bookmarkId: bookmarkId)
            guard !highlights.isEmpty else { return }
            highlights = highlights.map { var h = $0; h.bookmarkTags = tags; return h }
            _save(highlights, bookmarkId: bookmarkId)
        }
    }

    func updateNote(id: UUID, bookmarkId: Int, note: String) {
        queue.sync {
            var highlights = _load(bookmarkId: bookmarkId)
            if let idx = highlights.firstIndex(where: { $0.id == id }) {
                highlights[idx].note = note.isEmpty ? nil : note
                _save(highlights, bookmarkId: bookmarkId)
            }
        }
    }

    private func _load(bookmarkId: Int) -> [Highlight] {
        guard let url = jsonURL(for: bookmarkId),
              fileManager.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode([Highlight].self, from: data)
        } catch {
            return []
        }
    }

    private func _save(_ highlights: [Highlight], bookmarkId: Int) {
        guard let url = jsonURL(for: bookmarkId) else { return }
        do {
            let data = try encoder.encode(highlights)
            try data.write(to: url, options: .atomic)
        } catch {
            return
        }

        if !highlights.isEmpty {
            writeMarkdownSidecar(highlights)
        } else if let mdURL = markdownURL(for: bookmarkId) {
            try? fileManager.removeItem(at: mdURL)
        }
    }

    private func stripMarkdownLinks(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]+)\]\([^)]*\)"#) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
    }

    private func writeMarkdownSidecar(_ highlights: [Highlight]) {
        guard let first = highlights.first,
              let mdURL = markdownURL(for: first.bookmarkId) else { return }

        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        let dateStr = dateFormatter.string(from: first.timestamp)

        var base = SettingsManager.shared.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base = String(base.dropLast()) }
        let linkdingUrl = "\(base)/bookmarks?details=\(first.bookmarkId)"

        let tags = (first.bookmarkTags ?? []).filter {
            !$0.hasPrefix(".") && !$0.hasPrefix("!") && !$0.hasPrefix("via:")
        }

        var md = "---\n"
        md += "type:\n  - article\n"
        md += "bookmarkId: \(first.bookmarkId)\n"
        md += "sourceUrl: \(first.bookmarkURL)\n"
        md += "linkdingUrl: \(linkdingUrl)\n"
        md += "source:\n  - linkding\n"
        md += "bookmarkTitle: \"\(first.bookmarkTitle)\"\n"
        if tags.isEmpty {
            md += "tags: []\n"
        } else {
            md += "tags:\n"
            for tag in tags { md += "  - \(tag)\n" }
        }
        md += "dateCreated: \(dateStr)\n"
        md += "researchStatus:\n  - new\n"
        md += "---\n\n"
        md += "# \(first.bookmarkTitle)\n\n"
        md += "## Metadata \n\n"
        md += "- URL: `=this.sourceUrl`\n"
        md += "- Linkding: `=this.linkdingUrl`\n"
        md += "- Tags: `=this.tags`\n"
        md += "\n"
        md += "## Highlights for \(first.bookmarkTitle)\n\n"

        for h in highlights {
            md += "> [!quote]+\n"
            md += ">\n"
            md += "> \(h.markdownText ?? h.selectedText)\n"
            if let note = h.note, !note.isEmpty {
                md += "> \n"
                for noteLine in note.components(separatedBy: "\n") {
                    md += "> > \(noteLine)\n"
                }
            }
            md += "\n"
        }

        try? md.write(to: mdURL, atomically: true, encoding: .utf8)
    }
}
