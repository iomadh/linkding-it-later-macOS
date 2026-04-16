//
//  ShareExtensionViewController.swift
//  ShareExtension
//

import Cocoa
import SwiftUI

@objc(ShareExtensionViewController)
class ShareExtensionViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        let hostingView = NSHostingView(
            rootView: ShareExtensionView(context: extensionContext!)
        )
        hostingView.frame = NSRect(x: 0, y: 0, width: 360, height: 220)
        self.view = hostingView
    }
}

// MARK: - Share Extension SwiftUI View

struct ShareExtensionView: View {
    let context: NSExtensionContext

    @State private var urlToSave: String = ""
    @State private var pageTitle: String = ""
    @State private var isSaving = false
    @State private var resultState: ResultState = .idle

    enum ResultState {
        case idle
        case saving
        case success
        case duplicate
        case error(String)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "bookmark")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Linkding It Later")
                    .font(.headline)
                Spacer()
            }

            if !urlToSave.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pageTitle.isEmpty ? urlToSave : pageTitle)
                        .font(.subheadline)
                        .lineLimit(2)
                    if !pageTitle.isEmpty {
                        Text(urlToSave)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }

            switch resultState {
            case .idle, .saving:
                HStack {
                    Button("Cancel") {
                        context.cancelRequest(withError: NSError(domain: "ShareExtension", code: 0))
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save Bookmark") {
                        saveBookmark()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(urlToSave.isEmpty || isSaving)
                    .overlay {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                    }
                }

            case .success:
                Label("Bookmark saved!", systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.subheadline.weight(.medium))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                            context.completeRequest(returningItems: nil)
                        }
                    }

            case .duplicate:
                VStack(spacing: 8) {
                    Label("Already saved", systemImage: "bookmark.fill")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Button("Close") {
                        context.completeRequest(returningItems: nil)
                    }
                    .buttonStyle(.bordered)
                }

            case .error(let message):
                VStack(spacing: 8) {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                    Button("Close") {
                        context.cancelRequest(withError: NSError(domain: "ShareExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: message]))
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { extractURL() }
    }

    private func extractURL() {
        guard let item = context.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else { return }

        // Try to get the URL attribute
        if let urlAttribute = item.attributedContentText?.string {
            urlToSave = urlAttribute
        }

        // Extract title from user info
        if let userInfo = item.userInfo,
           let pageTitle = userInfo["pageTitle"] as? String {
            self.pageTitle = pageTitle
        }

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier("public.url") {
                attachment.loadItem(forTypeIdentifier: "public.url", options: nil) { item, _ in
                    if let url = item as? URL {
                        DispatchQueue.main.async { self.urlToSave = url.absoluteString }
                    } else if let urlString = item as? String {
                        DispatchQueue.main.async { self.urlToSave = urlString }
                    }
                }
                return
            }
        }
    }

    private func saveBookmark() {
        guard !urlToSave.isEmpty else { return }
        isSaving = true
        resultState = .saving

        Task {
            do {
                try await LinkdingService.shared.createBookmark(
                    url: urlToSave,
                    tags: [],
                    notes: "",
                    unread: true
                )
                await MainActor.run { resultState = .success }
            } catch let error as NetworkError {
                await MainActor.run {
                    switch error {
                    case .httpError(let code) where code == 400:
                        resultState = .duplicate
                    default:
                        resultState = .error(error.localizedDescription)
                    }
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    resultState = .error(error.localizedDescription)
                    isSaving = false
                }
            }
        }
    }
}
