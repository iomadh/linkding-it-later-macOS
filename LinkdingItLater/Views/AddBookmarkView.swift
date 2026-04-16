//
//  AddBookmarkView.swift
//  Linkding It Later
//

import SwiftUI

struct AddBookmarkView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var tags: [String] = []
    @State private var newTagText = ""
    @State private var notes = ""
    @State private var markAsRead = false
    @State private var availableTags: [String] = []
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var isURLFieldFocused: Bool

    let onSave: () -> Void

    private var filteredSuggestions: [String] {
        guard !newTagText.isEmpty else { return [] }
        let lowercasedInput = newTagText.lowercased()
        return availableTags
            .filter { $0.lowercased().hasPrefix(lowercasedInput) && !tags.contains($0) }
            .prefix(5)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("URL") {
                    TextField("https://...", text: $url)
                        .autocorrectionDisabled()
                        .focused($isURLFieldFocused)
                }

                Section("Tags") {
                    if !tags.isEmpty {
                        FlowLayout(spacing: 8) {
                            ForEach(tags, id: \.self) { tag in
                                TagPill(tag: tag) {
                                    withAnimation { tags.removeAll { $0 == tag } }
                                }
                            }
                        }
                    }

                    TextField("Add tag...", text: $newTagText)
                        .autocorrectionDisabled()
                        .onSubmit { addTag(newTagText) }

                    if !filteredSuggestions.isEmpty {
                        ForEach(filteredSuggestions, id: \.self) { suggestion in
                            Button {
                                addTag(suggestion)
                            } label: {
                                HStack {
                                    Image(systemName: "tag").foregroundColor(.secondary)
                                    Text(suggestion).foregroundColor(.primary)
                                }
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Toggle("Mark as read", isOn: $markAsRead)
                }

                if let error = errorMessage {
                    Section {
                        Text(error).foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Add Bookmark")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveBookmark() }
                        .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
                }
            }
            .onAppear { isURLFieldFocused = true }
            .task {
                availableTags = (try? await LinkdingService.shared.fetchAllTags()) ?? []
            }
        }
        .frame(minWidth: 400, minHeight: 400)
    }

    private func addTag(_ tag: String) {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else {
            newTagText = ""
            return
        }
        withAnimation { tags.append(trimmed) }
        newTagText = ""
    }

    private func saveBookmark() {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return }

        isSaving = true
        errorMessage = nil

        Task {
            do {
                try await LinkdingService.shared.createBookmark(
                    url: trimmedURL,
                    tags: tags,
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    unread: !markAsRead
                )
                await MainActor.run {
                    onSave()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
