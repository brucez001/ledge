<p align="center">
  <img src="Assets/AppIcon-256.png" width="160" height="160" alt="Ledge app icon">
</p>

<h1 align="center">Ledge</h1>

<p align="center">
  Your web apps, parked at the edge of your Mac.
</p>

<p align="center">
  A native, local-only slide-over web panel for macOS.
</p>

Ledge keeps the web apps you reach for all day — chat, music, dashboards,
mail, documentation — one hover or hotkey away. Each saved site gets a warm,
persistent WebKit session, so switching sites or hiding the panel does not
discard its state.

No server. No account. No telemetry. No third-party dependencies.

> [!NOTE]
> Ledge is currently distributed as a source build. Signed release downloads
> and an automatic updater are not available yet.

## Highlights

- **Lives on a screen edge** — dock left or right and reveal by edge hover or
  the global **⇧⌘Space** shortcut.
- **Keeps sites warm** — saved sites retain their `WKWebView` sessions while
  hidden or inactive, allowing media and long-running pages to continue.
- **Fast site rail** — switch, reorder, rename, reload, pin, or close sessions
  without returning to a browser window.
- **Transient tabs** — open one-off pages with **⌘T** without adding them to
  your saved sites.
- **Focused browser controls** — an auto-hiding toolbar, omnibox, find in page,
  zoom, downloads, desktop/mobile user agents, and external-app links.
- **Multi-display aware** — follows the pointer by default, ignores interior
  display seams, and recovers when a display is disconnected.
- **Native and private** — built with SwiftUI, AppKit, and WebKit; settings,
  favourites, cookies, and caches remain on the Mac. Optional favicon lookups
  are explained under [Privacy](#privacy).

## Requirements

- macOS 14 Sonoma or later
- Xcode command-line tools
- Swift 6 toolchain

Install the command-line tools if needed:

```zsh
xcode-select --install
```

## Build and run

Clone the repository, then run Ledge directly with Swift Package Manager:

```zsh
git clone https://github.com/brucez001/ledge.git
cd ledge
swift run
```

For a double-clickable local app bundle:

```zsh
Scripts/build-local-app.sh --open
```

The script builds, packages, and ad-hoc signs `build/Ledge.app`. To also replace
the copy in `~/Applications`:

```zsh
Scripts/build-local-app.sh --install --open
```

Launch at login and website camera/microphone permission prompts require the app
bundle; they are not available when running through `swift run`. The command-line
and app-bundle forms also use different `UserDefaults` domains, so favourites and
settings do not automatically carry between them.

## Using Ledge

1. Open Ledge and add a website from the home screen.
2. Move the pointer to the docked screen edge, or press **⇧⌘Space**, to reveal
   the panel.
3. Select saved sites from the rail. Their live sessions remain loaded when you
   switch away or hide the panel.
4. Drag the panel across the display midpoint to dock it on the opposite edge.
5. Use the pin control to keep the panel open, or leave auto-hide enabled so it
   retreats when you click elsewhere.

Only outside edges of a multi-display desktop respond to hover. An interior
boundary is a display seam, so Ledge deliberately does not arm it; the global
hotkey can still reveal Ledge on the display under the pointer.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘Space | Show or hide Ledge |
| ⌘1 – ⌘9 | Open the corresponding saved site |
| ⇧⌘H | Go home |
| ⌘L | Focus the address or search field |
| ⌘T | Open a transient tab |
| ⌘W | Close the current transient tab |
| ⌘R | Reload the current page |
| ⌘F | Find in page |
| ⌘[ / ⌘← | Back |
| ⌘] / ⌘→ | Forward |
| ⌘+ / ⌘= / ⌘- | Zoom in or out |
| ⌘0 | Reset zoom while browsing; otherwise go home |
| ⇧⌘C | Copy the current URL |
| ⇧⌘O | Open the current page in the default browser |
| Esc | Dismiss the current layer, return home, or hide the panel |

`⌘W` never closes a saved site's live session, the panel, or the app.

## Sites, sessions, and browsing

Each saved site owns a persistent `WKWebView`. All web views share one WebKit
data store, so a sign-in is available across Ledge, while each site's navigation
and page state remain independent. Sites can use desktop or mobile user agents
and optionally reload whenever they are shown.

Transient tabs are intentionally temporary and are not restored on the next
launch. An empty transient tab is reused rather than allowing stacks of blank
tabs, and it can be pinned into a saved site once it has navigated somewhere.

The omnibox recognises normal URLs, ports, IP addresses, `localhost`, and local
files. Other input is sent to the configured search engine: Google,
DuckDuckGo, Bing, Kagi, or Startpage.

## Privacy

Ledge has no backend, account system, analytics, telemetry, advertising,
payment flow, licence check, or update service.

Network traffic is limited to:

- websites you choose to open; and
- site-icon requests, according to the favicon source selected in Settings.

Icons are requested from the site itself first. By default, unresolved icons may
fall back to Google’s favicon service, which sends that site’s domain to Google.
Choose **Site only** or **Letter tiles only** in Privacy settings to disable this
third-party fallback.

Website cookies and sign-ins are stored by macOS WebKit. Favourites and
preferences use `UserDefaults`; favicon data is cached under Application
Support. Settings includes controls to close live sessions, clear caches, and
clear all website data.

## Deliberate scope

Ledge is intended to remain a focused edge browser rather than a general
notification or workspace platform. The following are deliberately out of
scope:

- per-site notification badges, sounds, and automatic audio muting;
- a permanently visible collapsed rail;
- cloud sync or a Ledge account; and
- licensing, trials, analytics, or an in-app payment system.

## Development

Useful commands:

```zsh
swift build                              # debug build
swift test                               # unit tests
Scripts/dev-check.sh                     # build and tests, concise output
Scripts/dev-check.sh --build-only        # build only
Scripts/generate-app-icon.sh             # regenerate PNG and ICNS icon assets
Scripts/build-local-app.sh               # package build/Ledge.app
```

The project has no third-party package dependencies.

### Project structure

```text
Assets/                    App icon source and generated assets
Sources/Ledge/
  Favicons/                Site icon discovery and cache
  Models/                  Saved-site data and persistence
  Sessions/                Web sessions, tabs, and address resolution
  Support/                 Preferences and app support
  Views/                   SwiftUI interface
  Windowing/               Panel, display-edge, hotkey, and menu-bar logic
Tests/LedgeTests/          Unit tests
Scripts/                   Build, packaging, and asset helpers
```

See [`AGENTS.md`](AGENTS.md) for the repository's implementation conventions
and behavioural contracts.

## Contributing

Issues and pull requests are welcome once the public repository is available.
For code changes:

1. keep the app local-only and dependency-free unless a change is explicitly
   discussed first;
2. add focused tests for behavioural logic;
3. run `swift test`; and
4. manually verify app-bundle-only, AppKit, and WebKit behaviour where relevant.

Please keep changes focused and update this README when commands, shortcuts,
privacy behaviour, requirements, or deliberate scope change.

## Licence

Ledge is available under the [MIT Licence](LICENSE). Copyright © 2026 Bruce Zhu.
