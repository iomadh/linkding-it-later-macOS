//
//  OfflineStatusBanner.swift
//  Linkding It Later
//

import SwiftUI

struct OfflineStatusBanner: View {
    let isOffline: Bool
    let pendingUpdateCount: Int
    let lastSyncDate: Date?
    let isSyncing: Bool
    var onSyncTapped: (() -> Void)?

    var body: some View {
        if isOffline || pendingUpdateCount > 0 || isSyncing {
            HStack(spacing: 8) {
                if isOffline {
                    Image(systemName: "wifi.slash")
                        .foregroundColor(.white)
                    Text("Offline")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.white)
                }

                if pendingUpdateCount > 0 {
                    if isOffline {
                        Text("-").foregroundColor(.white.opacity(0.7))
                    }
                    Text("\(pendingUpdateCount) pending")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }

                if isSyncing {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Syncing...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer()

                if let date = lastSyncDate {
                    Text("Cached \(timeAgoText(from: date))")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }

                if !isOffline && pendingUpdateCount > 0 && !isSyncing {
                    Button {
                        onSyncTapped?()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bannerColor)
        }
    }

    private var bannerColor: Color {
        if isOffline { return .orange }
        if isSyncing { return .blue }
        return Color(NSColor.secondaryLabelColor)
    }

    private func timeAgoText(from date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}
