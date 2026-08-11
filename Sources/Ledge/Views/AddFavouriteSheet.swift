import AppKit
import SwiftUI

/// Adds a Home shortcut with a required address and optional display name.
struct AddFavouriteSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FavouritesStore

    @State private var address = ""
    @State private var name = ""
    @State private var clipboardSuggestion: String?
    @FocusState private var addressFocused: Bool

    private var normalizedAddress: String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.lowercased().hasPrefix("http://") || trimmed.lowercased().hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }

    private var resolvedHost: String? {
        guard let url = URL(string: normalizedAddress), let host = url.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private var defaultName: String { resolvedHost ?? "" }

    private var isValid: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && resolvedHost != nil
    }

    /// Only shown once the user has typed something, so the message never
    /// flashes on an empty, freshly-opened sheet.
    private var validationMessage: String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, resolvedHost == nil else { return nil }
        return "Enter a valid website address, like notion.so or https://example.com."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add favourite")
                .font(.system(size: 22, weight: .bold, design: .rounded))

            HStack(spacing: 12) {
                FaviconView(host: resolvedHost ?? "", size: 34)
                    .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 6) {
                    TextField("Website address (e.g. notion.so)", text: $address)
                        .textFieldStyle(.roundedBorder)
                        .focused($addressFocused)

                    if let validationMessage {
                        Text(validationMessage)
                            .font(.caption)
                            .foregroundStyle(Theme.dangerInk)
                    }
                }
            }

            if let clipboardSuggestion {
                clipboardSuggestionRow(clipboardSuggestion)
            }

            TextField(
                defaultName.isEmpty ? "Name (optional)" : "Name (optional — defaults to \"\(defaultName)\")",
                text: $name
            )
            .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: addFavourite)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 420)
        .task {
            addressFocused = true
            offerClipboardAddressIfAny()
        }
    }

    private func clipboardSuggestionRow(_ suggestion: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .foregroundStyle(Theme.inkSecondary)
            Text("Use copied link? \(suggestion)")
                .font(.caption)
                .foregroundStyle(Theme.inkSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button("Use") {
                address = suggestion
                clipboardSuggestion = nil
            }
            .buttonStyle(.borderless)
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    /// Offers (never forces) a pasteboard URL, so a copied link can become
    /// a favourite in one fewer step without ever silently overwriting
    /// whatever the user might already be typing.
    private func offerClipboardAddressIfAny() {
        guard address.isEmpty,
              let clipboardText = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: clipboardText),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else { return }
        clipboardSuggestion = clipboardText
    }

    private func addFavourite() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? defaultName : trimmedName
        store.add(name: finalName, address: normalizedAddress)
        dismiss()
    }
}
