//
//  BookmarkRowView.swift
//  Linkding It Later
//

import SwiftUI

struct BookmarkRowView: View {
    let bookmark: Bookmark

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoFormatterNoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                Text(displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                Text(relativeDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(displaySubtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .lineLimit(2)

            if !bookmark.tagNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bookmark.tagNames, id: \.self) { tag in
                            Text(tag)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundColor(.blue)
                                .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var displayTitle: String {
        if !bookmark.title.isEmpty { return bookmark.title }
        if let t = bookmark.websiteTitle, !t.isEmpty { return t }
        return bookmark.url
    }

    private var displaySubtitle: String {
        if !bookmark.description.isEmpty { return bookmark.description }
        if let d = bookmark.websiteDescription, !d.isEmpty { return d }
        return bookmark.url
    }

    private var relativeDate: String {
        guard let date = Self.isoFormatter.date(from: bookmark.dateAdded)
                ?? Self.isoFormatterNoFraction.date(from: bookmark.dateAdded) else { return "" }

        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let daysDiff = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        if daysDiff < 7 {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        }

        let monthsDiff = calendar.dateComponents([.month], from: date, to: now).month ?? 0
        let yearsDiff = calendar.dateComponents([.year], from: date, to: now).year ?? 0

        if monthsDiff >= 1 && yearsDiff < 1 {
            return monthsDiff == 1 ? "1 month ago" : "\(monthsDiff) months ago"
        }
        if yearsDiff < 1 {
            let weeks = daysDiff / 7
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }
        return yearsDiff == 1 ? "1 year ago" : "\(yearsDiff) years ago"
    }
}
