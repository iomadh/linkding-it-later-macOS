//
//  Highlight.swift
//  Linkding It Later
//

import Foundation

struct Highlight: Identifiable, Codable, Equatable {
    let id: UUID
    let bookmarkId: Int
    let selectedText: String   // plain text — used for DOM highlighting and display
    var markdownText: String?  // markdown-formatted text (e.g. with [link](url)) — written to .md file
    var note: String?
    let timestamp: Date
    let bookmarkTitle: String
    let bookmarkURL: String
    var bookmarkTags: [String]? // bookmark tags at time of last write — optional for JSON backward compat
}
