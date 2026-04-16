//
//  TagEditingView.swift
//  Linkding It Later
//

import SwiftUI

struct TagEditingView: View {
    let bookmarkId: Int
    let initialTags: [String]
    let availableTags: [String]
    let onSave: ([String]) -> Void

    private let quickSelectTags = [
        "!action", "!fiction", "!laptop", "!listen", "!long",
        "!reply", "!research", "!spoilers", "!watch", "!work"
    ]

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String]
    @State private var newTagText = ""
    @State private var isSaving = false
    @State private var selectedSuggestionIndex: Int? = nil
    @FocusState private var isTextFieldFocused: Bool

    init(bookmarkId: Int, initialTags: [String], availableTags: [String], onSave: @escaping ([String]) -> Void) {
        self.bookmarkId = bookmarkId
        self.initialTags = initialTags
        self.availableTags = availableTags
        self.onSave = onSave
        _tags = State(initialValue: initialTags)
    }

    private var filteredSuggestions: [String] {
        guard !newTagText.isEmpty else { return [] }
        let lowercasedInput = newTagText.lowercased()
        return availableTags
            .filter { $0.lowercased().hasPrefix(lowercasedInput) && !tags.contains($0) }
            .prefix(10)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Current Tags") {
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
                        .focused($isTextFieldFocused)
                        .onChange(of: newTagText) { _, _ in
                            selectedSuggestionIndex = nil
                        }
                        .onKeyPress(.downArrow) {
                            guard !filteredSuggestions.isEmpty else { return .ignored }
                            if let idx = selectedSuggestionIndex {
                                selectedSuggestionIndex = min(idx + 1, filteredSuggestions.count - 1)
                            } else {
                                selectedSuggestionIndex = 0
                            }
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            if let idx = selectedSuggestionIndex, idx > 0 {
                                selectedSuggestionIndex = idx - 1
                            } else {
                                selectedSuggestionIndex = nil
                            }
                            return .handled
                        }
                        .onKeyPress(.return) {
                            if let idx = selectedSuggestionIndex, idx < filteredSuggestions.count {
                                addTag(filteredSuggestions[idx])
                                selectedSuggestionIndex = nil
                                isTextFieldFocused = true
                                return .handled
                            }
                            let trimmed = newTagText.trimmingCharacters(in: .whitespaces)
                            if !trimmed.isEmpty {
                                addTag(trimmed)
                                isTextFieldFocused = true
                                return .handled
                            }
                            // Empty field, no suggestion selected → Done
                            onSave(tags)
                            dismiss()
                            return .handled
                        }

                    if !filteredSuggestions.isEmpty {
                        ForEach(Array(filteredSuggestions.enumerated()), id: \.element) { index, suggestion in
                            Button {
                                addTag(suggestion)
                                isTextFieldFocused = true
                            } label: {
                                HStack {
                                    Image(systemName: "tag").foregroundColor(.secondary)
                                    Text(suggestion).foregroundColor(.primary)
                                    Spacer()
                                }
                                .padding(.vertical, 2)
                                .padding(.horizontal, 4)
                                .background(selectedSuggestionIndex == index ? Color.accentColor.opacity(0.15) : Color.clear)
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Quick Select") {
                    FlowLayout(spacing: 8) {
                        ForEach(quickSelectTags, id: \.self) { tag in
                            QuickSelectPill(tag: tag, isSelected: tags.contains(tag)) {
                                toggleQuickTag(tag)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Tags")
            .onAppear { isTextFieldFocused = true }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(tags)
                        dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private func toggleQuickTag(_ tag: String) {
        withAnimation {
            if tags.contains(tag) { tags.removeAll { $0 == tag } }
            else { tags.append(tag) }
        }
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
}

// MARK: - Tag Pill

struct TagPill: View {
    let tag: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag).font(.callout)
            Button { onRemove() } label: {
                Image(systemName: "xmark.circle.fill").font(.callout)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.blue.opacity(0.1))
        .foregroundColor(.blue)
        .cornerRadius(16)
    }
}

// MARK: - Quick Select Pill

struct QuickSelectPill: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button { onTap() } label: {
            Text(tag)
                .font(.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.clear)
                .foregroundColor(isSelected ? .white : .secondary)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + result.positions[index].x,
                            y: bounds.minY + result.positions[index].y),
                proposal: .unspecified
            )
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}
