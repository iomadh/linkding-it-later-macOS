//
//  Bookmark.swift
//  LinkdingosApp
//

import Foundation

struct Bookmark: Identifiable, Codable, Equatable, Hashable {
    let id: Int
    let url: String
    let title: String
    let description: String
    let notes: String
    let isArchived: Bool
    let unread: Bool
    let shared: Bool
    let tagNames: [String]
    let dateAdded: String
    let dateModified: String
    let websiteTitle: String?
    let websiteDescription: String?
    let faviconUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, url, title, description, notes, shared, unread
        case isArchived = "is_archived"
        case tagNames = "tag_names"
        case dateAdded = "date_added"
        case dateModified = "date_modified"
        case websiteTitle = "website_title"
        case websiteDescription = "website_description"
        case faviconUrl = "favicon_url"
    }
}

struct BookmarkResponse: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [Bookmark]
}
