# AGENTS.md

## Project

Ledge is a native, local-only macOS slide-over web panel. It is a Swift 6
package targeting macOS 14 and uses AppKit, SwiftUI, WebKit, and system
frameworks only.

Preserve the core product contract:

- local-only: no server, account, analytics, telemetry, payment, or licence flow;
- no third-party runtime dependencies without explicit approval;
- the rail contains open sessions only; every rail item shares the same close,
  menu, reordering, and keyboard behaviour;
- favourites are Home shortcuts only: adding or removing one must not create,
  close, or otherwise change an already-open session;
- open sessions keep their `WKWebView` until the user closes them, and no
  sessions are restored across launches;
- the app remains an accessory app with no Dock or app-switcher presence;
- outside display edges may reveal the panel; interior multi-display seams may not;
- `⌘W` closes the current session, but never removes its Home favourite or
  closes the panel or app.

## Commands

Run from the repository root:

```zsh
swift build
swift test
Scripts/dev-check.sh
Scripts/generate-app-icon.sh
Scripts/build-local-app.sh
```

Use `Scripts/build-local-app.sh --open` for behaviour that only works from an
app bundle, including launch-at-login and camera/microphone permission prompts.
The generated app lives at `build/Ledge.app`.

## Source layout

- `Sources/Ledge/App.swift` — app lifecycle and global controllers
- `Sources/Ledge/Windowing/` — panel, display-edge, hotkey, and menu-bar behaviour
- `Sources/Ledge/Sessions/` — persistent web sessions, tabs, and address resolution
- `Sources/Ledge/Views/` — SwiftUI interface
- `Sources/Ledge/Favicons/` — site icon discovery and caching
- `Sources/Ledge/Models/` — saved-site model and persistence
- `Sources/Ledge/Support/` — preferences and app support
- `Tests/LedgeTests/` — unit tests
- `Scripts/` — local build, packaging, and verification helpers

## Implementation conventions

- Keep UI-bound controllers and observable stores `@MainActor`.
- Prefer small, purpose-specific types over adding responsibilities to
  `PanelController`.
- Keep AppKit window/event behaviour separate from SwiftUI presentation.
- Do not recreate an open session's `WKWebView` merely because the panel hides
  or another session is selected.
- New persisted settings must use the `ledge.` key prefix and receive coverage
  for defaults, invalid stored values, and migration when applicable.
- User-facing destructive actions must be explicit and confirmed.
- Preserve macOS keyboard conventions and accessibility labels.
- Use Australian English in documentation and user-facing prose.
- Avoid references that frame Ledge as a clone of another commercial product.

## Testing

- Add focused unit coverage for behavioural changes where the logic can be
  separated from AppKit/WebKit UI.
- Run `swift test` before considering a change complete.
- For windowing, hover, focus, media, permissions, or WebKit-session changes,
  also build the app bundle and perform a manual macOS check.
- Do not treat a successful `swift run` as proof of bundle-only behaviour.

## Repository hygiene

- Do not commit `.build/`, `build/`, `DerivedData/`, user data, cookies, caches,
  signing identities, or local configuration.
- Do not commit generated app bundles.
- When `Assets/AppIcon.svg` changes, run `Scripts/generate-app-icon.sh` and
  commit the matching PNG and ICNS outputs.
- Keep unrelated workspace changes intact.
- Update `README.md` when commands, requirements, privacy behaviour, shortcuts,
  or deliberate scope change.
