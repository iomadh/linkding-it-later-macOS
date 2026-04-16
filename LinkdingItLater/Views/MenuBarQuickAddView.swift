//
//  MenuBarQuickAddView.swift
//  Linkding It Later
//

import SwiftUI

struct MenuBarQuickAddView: View {
    @State private var url = ""
    @State private var tags: [String] = []
    @State private var newTagText = ""
    @State private var isSaving = false
    @State private var resultMessage: String?
    @State private var resultIsError = false
    @FocusState private var isURLFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Bookmark")
                .font(.headline)

            TextField("URL to bookmark", text: $url)
                .textFieldStyle(.roundedBorder)
                .focused($isURLFocused)
                .onSubmit {
                    if !url.isEmpty { save() }
                }

            if !tags.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 3) {
                            Text(tag)
                                .font(.caption)
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(10)
                    }
                }
            }

            TextField("Add tag (press Return)", text: $newTagText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit {
                    let trimmed = newTagText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if !trimmed.isEmpty && !tags.contains(trimmed) {
                        tags.append(trimmed)
                    }
                    newTagText = ""
                }

            if let msg = resultMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(resultIsError ? .red : .green)
            }

            HStack {
                Button("Open App") {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows {
                        if window.canBecomeMain {
                            window.makeKeyAndOrderFront(nil)
                            break
                        }
                    }
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(url.isEmpty || isSaving)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(16)
        .frame(width: 320)
        .onAppear { isURLFocused = true }
    }

    private func save() {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        isSaving = true
        resultMessage = nil

        Task {
            do {
                try await LinkdingService.shared.createBookmark(
                    url: trimmedURL,
                    tags: tags,
                    notes: "",
                    unread: true
                )
                await MainActor.run {
                    resultMessage = "Saved!"
                    resultIsError = false
                    url = ""
                    tags = []
                    isSaving = false
                    // Auto-clear success message
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if resultMessage == "Saved!" { resultMessage = nil }
                    }
                }
            } catch {
                await MainActor.run {
                    resultMessage = error.localizedDescription
                    resultIsError = true
                    isSaving = false
                }
            }
        }
    }
}
