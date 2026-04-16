//
//  LinkdingItLaterApp.swift
//  Linkding It Later
//

import SwiftUI

extension Notification.Name {
    static let addBookmark = Notification.Name("addBookmark")
    static let refreshBookmarks = Notification.Name("refreshBookmarks")
    static let navigateNextUnread = Notification.Name("navigateNextUnread")
}

@main
struct LinkdingItLaterApp: App {
    private let backgroundScheduler = BackgroundSyncScheduler()

    init() {
        NetworkMonitor.shared.start()
        backgroundScheduler.schedule()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    Task { @MainActor in
                        OfflineCacheManager.shared.startPeriodicRefresh()
                        await OfflineCacheManager.shared.syncPendingUpdates()
                        _ = try? await OfflineCacheManager.shared.fetchBookmarks(unreadOnly: true, notifyOnUpdate: true)
                    }
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Bookmark") {
                    NotificationCenter.default.post(name: .addBookmark, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Refresh") {
                    NotificationCenter.default.post(name: .refreshBookmarks, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .frame(minWidth: 400, minHeight: 300)
        }

        MenuBarExtra("Linkding It Later", systemImage: "bookmark") {
            MenuBarQuickAddView()
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Background Sync

final class BackgroundSyncScheduler {
    private var activity: NSBackgroundActivityScheduler?

    func schedule() {
        let act = NSBackgroundActivityScheduler(identifier: "com.dellah.linkdingitlater.sync")
        act.repeats = true
        act.interval = 15 * 60
        act.qualityOfService = .utility
        act.schedule { completion in
            Task { @MainActor in
                await OfflineCacheManager.shared.syncPendingUpdates()
                _ = try? await OfflineCacheManager.shared.fetchBookmarks(unreadOnly: true, notifyOnUpdate: true)
                completion(.finished)
            }
        }
        self.activity = act
    }
}
