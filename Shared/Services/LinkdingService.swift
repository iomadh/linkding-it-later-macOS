//
//  LinkdingService.swift
//  LinkdingosApp
//

import Foundation

protocol LinkdingServiceProtocol {
    func fetchBookmarks(unreadOnly: Bool) async throws -> [Bookmark]
    @discardableResult
    func createBookmark(url: String, tags: [String], notes: String, unread: Bool) async throws -> Bookmark
    func setUnreadStatus(bookmarkId: Int, unread: Bool) async throws
    func updateBookmarkTags(bookmarkId: Int, tags: [String]) async throws
    func updateBookmarkNotes(bookmarkId: Int, notes: String) async throws
    func fetchAllTags() async throws -> [String]
    func refreshBookmarkMetadata(bookmarkId: Int, url: String) async throws -> (title: String?, description: String?)
    func updateBookmark(bookmarkId: Int, title: String?, description: String?, notes: String?, unread: Bool?, shared: Bool?) async throws
    func deleteBookmark(bookmarkId: Int) async throws
    func checkURL(_ url: String) async throws -> (existingBookmark: Bookmark?, metadata: (title: String?, description: String?))
}

final class LinkdingService: LinkdingServiceProtocol {
    static let shared = LinkdingService()

    private let settings: SettingsManager
    private let session: URLSession

    init(settings: SettingsManager = .shared, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    func fetchBookmarks(unreadOnly: Bool = true) async throws -> [Bookmark] {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/"

        guard var components = URLComponents(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var queryItems = [URLQueryItem(name: "limit", value: "1000")]
        if unreadOnly {
            queryItems.append(URLQueryItem(name: "unread", value: "yes"))
        }
        components.queryItems = queryItems

        guard let initialURL = components.url else {
            throw NetworkError.invalidURL
        }

        var allBookmarks: [Bookmark] = []
        var nextURL: URL? = initialURL
        let decoder = JSONDecoder()

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw NetworkError.networkError(underlying: error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401, 403:
                throw NetworkError.unauthorized
            default:
                throw NetworkError.httpError(statusCode: httpResponse.statusCode)
            }

            do {
                let bookmarkResponse = try decoder.decode(BookmarkResponse.self, from: data)
                allBookmarks.append(contentsOf: bookmarkResponse.results)

                // Check for next page
                if let nextString = bookmarkResponse.next, let next = URL(string: nextString) {
                    nextURL = next
                } else {
                    nextURL = nil
                }
            } catch {
                throw NetworkError.decodingError(underlying: error)
            }
        }

        return allBookmarks
    }

    @discardableResult
    func createBookmark(url: String, tags: [String] = [], notes: String = "", unread: Bool = true) async throws -> Bookmark {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/"

        guard let requestURL = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "url": url,
            "unread": unread
        ]
        if !tags.isEmpty {
            body["tag_names"] = tags
        }
        if !notes.isEmpty {
            body["notes"] = notes
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 201:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            let bookmark = try JSONDecoder().decode(Bookmark.self, from: data)
            return bookmark
        } catch {
            throw NetworkError.decodingError(underlying: error)
        }
    }

    func setUnreadStatus(bookmarkId: Int, unread: Bool) async throws {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/\(bookmarkId)/"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = ["unread": unread]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 204:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func updateBookmarkTags(bookmarkId: Int, tags: [String]) async throws {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/\(bookmarkId)/"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["tag_names": tags]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 204:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func updateBookmarkNotes(bookmarkId: Int, notes: String) async throws {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/\(bookmarkId)/"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["notes": notes]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 204:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func fetchAllTags() async throws -> [String] {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/tags/"

        guard var components = URLComponents(string: urlString) else {
            throw NetworkError.invalidURL
        }

        components.queryItems = [URLQueryItem(name: "limit", value: "1000")]

        guard let initialURL = components.url else {
            throw NetworkError.invalidURL
        }

        var allTags: [String] = []
        var nextURL: URL? = initialURL

        while let url = nextURL {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw NetworkError.networkError(underlying: error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401, 403:
                throw NetworkError.unauthorized
            default:
                throw NetworkError.httpError(statusCode: httpResponse.statusCode)
            }

            // Parse response: {"count": N, "next": "url", "results": [{"id": 1, "name": "tagname"}, ...]}
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [[String: Any]] else {
                throw NetworkError.decodingError(underlying: NSError(domain: "TagParsing", code: 0))
            }

            let tags = results.compactMap { $0["name"] as? String }
            allTags.append(contentsOf: tags)

            // Check for next page
            if let nextString = json["next"] as? String, let next = URL(string: nextString) {
                nextURL = next
            } else {
                nextURL = nil
            }
        }

        return allTags.sorted()
    }

    func refreshBookmarkMetadata(bookmarkId: Int, url: String) async throws -> (title: String?, description: String?) {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        // Step 1: Check URL to get fresh metadata
        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/check/"

        guard var components = URLComponents(string: urlString) else {
            throw NetworkError.invalidURL
        }

        components.queryItems = [URLQueryItem(name: "url", value: url)]

        guard let checkURL = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: checkURL)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        // Parse the metadata response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = json["metadata"] as? [String: Any] else {
            throw NetworkError.decodingError(underlying: NSError(domain: "MetadataParsing", code: 0))
        }

        let title = metadata["title"] as? String
        let description = metadata["description"] as? String

        // Step 2: Update the bookmark with new metadata
        if title != nil || description != nil {
            try await updateBookmark(bookmarkId: bookmarkId, title: title, description: description, notes: nil, unread: nil, shared: nil)
        }

        return (title, description)
    }

    func updateBookmark(bookmarkId: Int, title: String?, description: String?, notes: String?, unread: Bool?, shared: Bool?) async throws {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/\(bookmarkId)/"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let title = title {
            body["title"] = title
        }
        if let description = description {
            body["description"] = description
        }
        if let notes = notes {
            body["notes"] = notes
        }
        if let unread = unread {
            body["unread"] = unread
        }
        if let shared = shared {
            body["shared"] = shared
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 204:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func deleteBookmark(bookmarkId: Int) async throws {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/\(bookmarkId)/"

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")

        let (_, response): (Data, URLResponse)
        do {
            (_, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200, 204:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    func checkURL(_ url: String) async throws -> (existingBookmark: Bookmark?, metadata: (title: String?, description: String?)) {
        guard settings.isConfigured else {
            throw NetworkError.serverNotConfigured
        }

        guard let token = settings.apiToken else {
            throw NetworkError.unauthorized
        }

        var urlString = settings.serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlString.hasSuffix("/") {
            urlString += "/"
        }
        urlString += "api/bookmarks/check/"

        guard var components = URLComponents(string: urlString) else {
            throw NetworkError.invalidURL
        }

        components.queryItems = [URLQueryItem(name: "url", value: url)]

        guard let checkURL = components.url else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: checkURL)
        request.httpMethod = "GET"
        request.setValue("Token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NetworkError.networkError(underlying: error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 401, 403:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NetworkError.decodingError(underlying: NSError(domain: "CheckURLParsing", code: 0))
        }

        // Parse metadata
        let metadata = json["metadata"] as? [String: Any]
        let title = metadata?["title"] as? String
        let description = metadata?["description"] as? String

        // Parse existing bookmark if present
        var existingBookmark: Bookmark? = nil
        if let bookmarkData = json["bookmark"], !(bookmarkData is NSNull) {
            let bookmarkJSON = try JSONSerialization.data(withJSONObject: bookmarkData)
            existingBookmark = try JSONDecoder().decode(Bookmark.self, from: bookmarkJSON)
        }

        return (existingBookmark, (title, description))
    }
}
