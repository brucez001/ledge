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
> Ledge is currently distributed as source code. There is no pre-built,
> signed download or automatic updater. Follow [Build and run](#build-and-run)
> below to create a local app bundle on your Mac.

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
- Full Xcode (for `actool`) if you want the app icon in bundles built on
  macOS 26 or later; without it the build still succeeds with a warning

Install the command-line tools if needed:

```zsh
xcode-select --install
```

## Build and run

### 1. Clone the source

Open Terminal and run:

```zsh
git clone https://github.com/brucez001/ledge.git
cd ledge
```

### 2. Build and install the app

The recommended command builds a release version, creates a local app bundle,
installs it in `~/Applications`, and opens it:

```zsh
Scripts/build-local-app.sh --install --open
```

The script:

1. builds Ledge with Swift Package Manager in release mode;
2. packages and ad-hoc signs `build/Ledge.app`;
3. copies it to `~/Applications/Ledge.app`; and
4. launches the installed copy.

To rebuild after pulling a newer version, run the same command again. It safely
replaces the existing copy in `~/Applications`.

If you only want to build and open the app without installing it:

```zsh
Scripts/build-local-app.sh --open
```

The resulting bundle remains at `build/Ledge.app`.

### Development run

During development, Ledge can also run directly through Swift Package Manager:

```zsh
swift run
```

Use the app-bundle build for normal use. Launch at login and website
camera/microphone permission prompts are unavailable through `swift run`.
The command-line and app-bundle forms also use different `UserDefaults`
domains, so favourites and settings do not carry between them automatically.

### Verify the source

To build and run the unit tests without launching the app:

```zsh
Scripts/dev-check.sh
```

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

Edge hover can be turned off at any time from the menu-bar item's **Reveal on
Edge Hover** entry, or in Settings. This is handy before sharing your screen: the
panel then only appears when you ask for it with **⇧⌘Space**, the menu bar, or a
site chosen from the **Sites** submenu.

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
tabs, and it can be added to your favourites once it has navigated somewhere.

Right-clicking a tab in the rail offers the same actions a saved site does,
wherever they make sense for something temporary: reload, desktop or mobile
user agent, reload when shown, copy address, open in the default browser, and
reordering.

A gap separates the saved sites from the tabs in the rail, and it divides what
dragging means. Dragged among the tabs, a tab is reordered. Dragged up across
the gap onto the saved sites, it is kept as a favourite at exactly that
position — the page carries on in the same web view rather than reloading.
**Add to Favourites** in the tab's menu does the same thing, adding it to the
end of the list.

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

Ledge's source code and original project assets, including the app icon, are
available under the [MIT Licence](LICENSE). Copyright © 2026 Bruce Zhu.

Names and trademarks belonging to websites or services mentioned in the
documentation remain the property of their respective owners.
