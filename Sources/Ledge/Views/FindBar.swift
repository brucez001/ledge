import SwiftUI

/// Compact find-in-page bar shown above the web content when
/// `controller.isShowingFindBar` is set. Kept separate from `BrowserPanel`
/// so it can be reused/tested on its own, and so `BrowserPanel` doesn't
/// grow into one giant view.
struct FindBar: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var session: WebSession

    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var noMatches: Bool {
        !query.isEmpty && session.lastFindMatched == false
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.inkTertiary)

            TextField("Find in page", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Theme.ink)
                .focused($isFocused)
                .onSubmit { session.find(query, forward: true) }
                .onChange(of: query) { _, newValue in
                    if newValue.isEmpty {
                        session.clearFind()
                    } else {
                        session.find(newValue, forward: true)
                    }
                }
                .onKeyPress(.escape) {
                    close()
                    return .handled
                }

            if noMatches {
                Text("No matches")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.dangerInk)
                    .fixedSize()
            }

            HStack(spacing: 2) {
                Button {
                    session.find(query, forward: false)
                } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .disabled(query.isEmpty)
                .help("Previous match")
                .accessibilityLabel("Previous match")

                Button {
                    session.find(query, forward: true)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .disabled(query.isEmpty)
                .help("Next match")
                .accessibilityLabel("Next match")
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.inkSecondary)

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.inkSecondary)
            .help("Close find bar")
            .accessibilityLabel("Close find bar")
        }
        .padding(.horizontal, 12)
        .frame(height: Theme.Metrics.findBarHeight)
        .background(Theme.chrome)
        .onChange(of: controller.findFocusToken) { _, _ in
            isFocused = true
        }
        .task {
            isFocused = true
        }
        .onDisappear {
            session.clearFind()
        }
    }

    private func close() {
        query = ""
        session.clearFind()
        controller.closeFindBar()
    }
}
