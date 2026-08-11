import AppKit
import SwiftUI

/// Shared wording for removing a Home shortcut.
enum FavouriteRemoval {
    static let menuTitle = "Remove from Favourites…"

    static func confirmationTitle(_ favourite: Favourite) -> String {
        "Remove \(favourite.name) from Favourites?"
    }

    static let confirmationMessage = "The Home shortcut will be removed. Any open session stays open."
}

extension View {
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
            Button("Remove from Favourites", role: .destructive, action: remove)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(FavouriteRemoval.confirmationMessage)
        }
    }

    func confirmFavouriteRemoval(
        _ favourite: Binding<Favourite?>,
        remove: @escaping (Favourite) -> Void
    ) -> some View {
        confirmationDialog(
            favourite.wrappedValue.map(FavouriteRemoval.confirmationTitle) ?? "Remove from Favourites?",
            isPresented: Binding(
                get: { favourite.wrappedValue != nil },
                set: { if !$0 { favourite.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let item = favourite.wrappedValue {
                Button("Remove from Favourites", role: .destructive) {
                    remove(item)
                    favourite.wrappedValue = nil
                }
            }
            Button("Cancel", role: .cancel) { favourite.wrappedValue = nil }
        } message: {
            Text(FavouriteRemoval.confirmationMessage)
        }
    }
}

/// Reordering for one open rail session.
struct RailReordering {
    let entry: RailEntry
    let controller: PanelController
    let canMoveUp: Bool
    let canMoveDown: Bool

    var isAvailable: Bool { canMoveUp || canMoveDown }

    @MainActor
    func moveUp() { controller.moveRailEntry(entry, by: -1) }

    @MainActor
    func moveDown() { controller.moveRailEntry(entry, by: 1) }
}

/// Home favourites are shortcuts only, so their menu only manages the
/// shortcut itself. Session controls live on the rail and browser surface.
struct FavouriteMenuItems: View {
    @ObservedObject var controller: PanelController
    let item: Favourite
    let confirmRemoval: () -> Void

    var body: some View {
        Button("Open") { controller.openFavourite(item) }
        Button("Open in New Session") {
            controller.openFavouriteInNewSession(item)
        }
        Button("Copy address") { copyAddress() }
        Button("Open in default browser") { openInDefaultBrowser() }

        Divider()

        Button(FavouriteRemoval.menuTitle, role: .destructive) {
            confirmRemoval()
        }
    }

    private func copyAddress() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.absoluteString, forType: .string)
    }

    private func openInDefaultBrowser() {
        guard !item.url.isFileURL else { return }
        NSWorkspace.shared.open(item.url)
    }
}

/// One menu for every open session in the rail.
struct RailSessionMenuItems: View {
    @ObservedObject var controller: PanelController
    @ObservedObject var session: WebSession
    let entry: RailEntry
    let reordering: RailReordering
    let confirmFavouriteRemoval: (Favourite) -> Void

    private var favourite: Favourite? {
        guard let id = session.id.favouriteID else { return nil }
        return controller.favourites.favourite(withID: id)
    }

    var body: some View {
        Button("Open") { controller.openSession(session.id) }
        // Bare verb, like the `Open` and `Reload` either side of it: the object
        // is the row that was right-clicked. It opens another independent
        // session on the same page; the Home shortcut is not copied or changed.
        Button("Duplicate") {
            guard let url = session.currentURL else { return }
            controller.openInNewSession(url, iconHost: session.iconHost)
        }
        .disabled(session.currentURL == nil)
        Button("Reload") { session.reload() }
            .disabled(session.currentURL == nil)

        Divider()

        Button("Copy address") { session.copyCurrentURL() }
            .disabled(session.currentURL == nil)
        Button("Open in default browser") { session.openInDefaultBrowser() }
            .disabled(session.currentURL == nil)

        if reordering.isAvailable {
            Divider()

            Button("Move Up") { reordering.moveUp() }
                .disabled(!reordering.canMoveUp)
            Button("Move Down") { reordering.moveDown() }
                .disabled(!reordering.canMoveDown)
        }

        Divider()

        if let favourite {
            Button(FavouriteRemoval.menuTitle, role: .destructive) {
                confirmFavouriteRemoval(favourite)
            }
        } else if let tabID = session.id.tabID {
            Button("Add to Favourites") { controller.pinTab(tabID) }
                .disabled(!controller.canPinTab(tabID))
        }

        Divider()

        Button("Close Session") { controller.closeSession(session.id) }
    }
}
