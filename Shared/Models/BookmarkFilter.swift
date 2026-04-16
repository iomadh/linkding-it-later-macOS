//
//  BookmarkFilter.swift
//  LinkdingosApp
//

import Foundation

struct BookmarkFilter: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var displayName: String
    var searchQuery: String
    var icon: String
    var order: Int
    var excludeExclamationTags: Bool
    var showDotTagSubFilters: Bool

    enum CodingKeys: String, CodingKey {
        case id, displayName, searchQuery, tagName, icon, order, excludeExclamationTags, showDotTagSubFilters
    }

    init(id: UUID = UUID(), displayName: String, searchQuery: String, icon: String, order: Int, excludeExclamationTags: Bool = false, showDotTagSubFilters: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.searchQuery = searchQuery
        self.icon = icon
        self.order = order
        self.excludeExclamationTags = excludeExclamationTags
        self.showDotTagSubFilters = showDotTagSubFilters
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        // Migration: read searchQuery or fall back to converting old tagName
        if let sq = try container.decodeIfPresent(String.self, forKey: .searchQuery) {
            searchQuery = sq
        } else if let tn = try container.decodeIfPresent(String.self, forKey: .tagName), !tn.isEmpty {
            searchQuery = "#\(tn)"
        } else {
            searchQuery = ""
        }
        icon = try container.decode(String.self, forKey: .icon)
        order = try container.decode(Int.self, forKey: .order)
        excludeExclamationTags = try container.decodeIfPresent(Bool.self, forKey: .excludeExclamationTags) ?? false
        showDotTagSubFilters = try container.decodeIfPresent(Bool.self, forKey: .showDotTagSubFilters) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(searchQuery, forKey: .searchQuery)
        try container.encode(icon, forKey: .icon)
        try container.encode(order, forKey: .order)
        try container.encode(excludeExclamationTags, forKey: .excludeExclamationTags)
        try container.encode(showDotTagSubFilters, forKey: .showDotTagSubFilters)
    }

    // MARK: - Search parsing

    private enum Token {
        case word(String)
        case phrase(String)
        case tag(String)
        case and, or, not
    }

    private indirect enum Expression {
        case word(String)
        case phrase(String)
        case tag(String)
        case and(Expression, Expression)
        case or(Expression, Expression)
        case not(Expression)
        case empty
    }

    private func tokenize(_ query: String) -> [Token] {
        var tokens: [Token] = []
        var index = query.startIndex

        while index < query.endIndex {
            // Skip whitespace
            if query[index].isWhitespace {
                index = query.index(after: index)
                continue
            }

            // Quoted phrase
            if query[index] == "\"" {
                let start = query.index(after: index)
                if let end = query[start...].firstIndex(of: "\"") {
                    let phrase = String(query[start..<end])
                    tokens.append(.phrase(phrase))
                    index = query.index(after: end)
                } else {
                    // Unterminated quote — treat rest as phrase
                    let phrase = String(query[start...])
                    tokens.append(.phrase(phrase))
                    break
                }
                continue
            }

            // Tag: starts with #
            if query[index] == "#" {
                let start = query.index(after: index)
                var end = start
                while end < query.endIndex && !query[end].isWhitespace && query[end] != "\"" {
                    end = query.index(after: end)
                }
                let tagName = String(query[start..<end])
                if !tagName.isEmpty {
                    tokens.append(.tag(tagName))
                }
                index = end
                continue
            }

            // Word (collect until whitespace or quote)
            var end = index
            while end < query.endIndex && !query[end].isWhitespace && query[end] != "\"" {
                end = query.index(after: end)
            }
            let word = String(query[index..<end])
            switch word.uppercased() {
            case "AND": tokens.append(.and)
            case "OR":  tokens.append(.or)
            case "NOT": tokens.append(.not)
            default:    tokens.append(.word(word))
            }
            index = end
        }

        return tokens
    }

    private func parse(_ tokens: [Token]) -> Expression {
        var pos = 0

        func parsePrimary() -> Expression {
            guard pos < tokens.count else { return .empty }

            // NOT prefix
            if case .not = tokens[pos] {
                pos += 1
                let operand = parsePrimary()
                return .not(operand)
            }

            let token = tokens[pos]
            pos += 1
            switch token {
            case .word(let w):   return .word(w)
            case .phrase(let p): return .phrase(p)
            case .tag(let t):    return .tag(t)
            default:             return .empty
            }
        }

        func parseAnd() -> Expression {
            var left = parsePrimary()
            while pos < tokens.count {
                // Consume explicit AND or treat adjacency as AND
                if case .and = tokens[pos] {
                    pos += 1
                    let right = parsePrimary()
                    left = .and(left, right)
                } else if case .or = tokens[pos] {
                    break
                } else if case .not = tokens[pos] {
                    let right = parsePrimary()
                    left = .and(left, right)
                } else if case .word = tokens[pos] {
                    let right = parsePrimary()
                    left = .and(left, right)
                } else if case .phrase = tokens[pos] {
                    let right = parsePrimary()
                    left = .and(left, right)
                } else if case .tag = tokens[pos] {
                    let right = parsePrimary()
                    left = .and(left, right)
                } else {
                    break
                }
            }
            return left
        }

        func parseOr() -> Expression {
            var left = parseAnd()
            while pos < tokens.count, case .or = tokens[pos] {
                pos += 1
                let right = parseAnd()
                left = .or(left, right)
            }
            return left
        }

        return parseOr()
    }

    private func evaluate(_ expr: Expression, bookmark: Bookmark) -> Bool {
        let searchableText = [
            bookmark.title,
            bookmark.description,
            bookmark.notes,
            bookmark.url
        ].joined(separator: " ").lowercased()

        func eval(_ e: Expression) -> Bool {
            switch e {
            case .empty:
                return true
            case .word(let w):
                return searchableText.contains(w.lowercased())
            case .phrase(let p):
                return searchableText.contains(p.lowercased())
            case .tag(let t):
                return bookmark.tagNames.contains { $0.lowercased() == t.lowercased() }
            case .and(let l, let r):
                return eval(l) && eval(r)
            case .or(let l, let r):
                return eval(l) || eval(r)
            case .not(let inner):
                return !eval(inner)
            }
        }

        return eval(expr)
    }

    private static func hasExcludedTag(_ bookmark: Bookmark) -> Bool {
        bookmark.tagNames.contains { $0.hasPrefix("!") }
    }

    func apply(to bookmarks: [Bookmark]) -> [Bookmark] {
        var result: [Bookmark]

        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            result = bookmarks
        } else {
            let tokens = tokenize(searchQuery)
            let expr = parse(tokens)
            result = bookmarks.filter { evaluate(expr, bookmark: $0) }
        }

        if excludeExclamationTags {
            result = result.filter { !Self.hasExcludedTag($0) }
        }

        return result
    }

    func count(in bookmarks: [Bookmark]) -> Int {
        apply(to: bookmarks).count
    }

    static var defaultFilters: [BookmarkFilter] {
        [
            BookmarkFilter(displayName: "Unread", searchQuery: "", icon: "tray", order: 0, excludeExclamationTags: true),
            BookmarkFilter(displayName: "Important", searchQuery: "#.important", icon: "star.fill", order: 1, excludeExclamationTags: true),
            BookmarkFilter(displayName: "Star", searchQuery: "#!star", icon: "star", order: 2, excludeExclamationTags: false),
            BookmarkFilter(displayName: "Long", searchQuery: "#!long", icon: "book", order: 3, excludeExclamationTags: false),
            BookmarkFilter(displayName: "Blogs", searchQuery: "#.blogs", icon: "doc.richtext", order: 4, excludeExclamationTags: true),
            BookmarkFilter(displayName: "Football", searchQuery: "#.football", icon: "sportscourt", order: 5, excludeExclamationTags: true),
            BookmarkFilter(displayName: "Magazine", searchQuery: "#.magazine", icon: "magazine", order: 6, excludeExclamationTags: true),
            BookmarkFilter(displayName: "News", searchQuery: "#.news", icon: "newspaper", order: 7, excludeExclamationTags: true),
            BookmarkFilter(displayName: "Newsletters", searchQuery: "#.newsletters", icon: "envelope", order: 8, excludeExclamationTags: true),
            BookmarkFilter(displayName: "Substack", searchQuery: "#.substack", icon: "envelope.open", order: 9, excludeExclamationTags: true),
        ]
    }
}
