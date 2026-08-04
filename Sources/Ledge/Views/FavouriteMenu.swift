import AppKit
import SwiftUI

/// The one vocabulary for removing a saved site.
///
/// The rail menu, the home-screen tile menu, and the favourites manager each
/// used to carry their own wording -- "Remove from sidebar…" against "Remove
/// favourite…", with two different explanations of what removal does. One
/// operation described three ways reads as three different operations, so the
/// strings live here and nowhere else.
enum FavouriteRemoval {
    /// Trailing ellipsis, per macOS convention: the item opens a confirmation
    /// rather than removing anything outright.
    static let menuTitle = "Remove from Favourites…"

    static func confirmationTitle(_ favourite: Favourite) -> String {
        "Remove “\(favourite.name)” from favourites?"
    }

    static let confirmationMessage = "Its live session, if any, is closed. "
        + "Signed-in cookies are kept, so signing back in later is not required. "
        + "This can't be undone."
}

extension View {
    /// The shared removal confirmation, so every entry point asks the same
    /// question and explains the same consequences.
    func confirmFavouriteRemoval(
        _ favourite: Favourite,
        isPresented: Binding<Bool>,
        remove: @escaping () -> Void
    ) -> some View {
        confirmationDialog(
            FavouriteRemoval.confirmationTitle(favourite),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(FavouriteRemoval.confirmationMessage)
        }
    }
}

/// Reordering for one rail row, passed in by whichever surface offers it.
///
/// Moves are expressed over the rail's unified list, so a saved site steps over
/// an interleaved tab exactly as it steps over another saved site. The home grid
/// shows favourites only and reorders by dragging tiles, so it passes `nil`.
struct RailReordering {
    let entry: RailEntry
    let controller: PanelController
    let canMoveUp: Bool
    let canMoveDown: Bool

    /// Nothing to offer when the row is the rail's only one.
    var isAvailable: Bool { canMoveUp || canMoveDown }

    @MainActor
    func moveUp() { controller.moveRailEntry(entry, by: -1) }

    @MainActor
    func moveDown() { controller.moveRailEntry(entry, by: 1) }
}

/// The saved-site context menu, shared by the rail and the home grid.
///
/// Both act on the same object, so they offer the same actions in the same
/// order; only reordering differs, since the grid reorders by dragging tiles
/// rather than by menu. The order also matches a transient tab's menu, so the
/// rail behaves consistently from top to bottom.
struct FavouriteMenuItems: View {
    @ObservedObject var controller: PanelController
    let item: Favourite
    let hasSession: Bool
    /// Only the rail offers menu reordering: a narrow strip of similar icons is
    /// a fiddly drag target, whereas the grid's tiles are not.
    var reordering: RailReordering?
    /// Raised instead of removing immediately, so the caller owns the
    /// confirmation state.
    let confirmRemoval: () -> Void

    private var session: WebSession? {
        controller.sessionManager.existingSession(for: .favourite(item.id))
    }

    var body: some View {
        Group {
            Button("Open") { controller.openFavourite(item) }
            if hasSession {
                Button("Reload") { session?.reload() }
            }

            Divider()

            Button(item.resolvedUserAgentMode.toggled.title) {
                controller.setUserAgentMode(item.resolvedUserAgentMode.toggled, for: item)
            }
            Toggle(
                "Reload when shown",
                isOn: Binding(
                    get: { item.resolvedReloadsOnFocus },
                    set: { controller.setReloadsOnFocus($0, for: item) }
                )
            )
            Button("Copy address") { copyAddress() }
            Button("Open in default browser") { openInDefaultBrowser() }
        }

        Group {
            if let reordering, reordering.isAvailable {
                Divider()

                Button("Move Up") { reordering.moveUp() }
                    .disabled(!reordering.canMoveUp)
                Button("Move Down") { reordering.moveDown() }
                    .disabled(!reordering.canMoveDown)
            }

            if hasSession {
                Divider()

                Button("Close live session") {
                    controller.sessionManager.closeSession(kind: .favourite(item.id))
                }
            }

            Divider()

            // Deliberately alone below a divider: a destructive item hit from
            // muscle memory (reaching for "Reload", say) is the single worst
            // outcome in this menu.
            Button(FavouriteRemoval.menuTitle, role: .destructive) {
                confirmRemoval()
            }
        }
    }

    /// Prefers the live page's address, so copying from a site that has
    /// navigated on gives what is on screen rather than its start page.
    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((session?.currentURL ?? item.url).absoluteString, forType: .string)
    }

    private func openInDefaultBrowser() {
        let url = session?.currentURL ?? item.url
        guard !url.isFileURL else { return }
        NSWorkspace.shared.open(url)
    }
}
