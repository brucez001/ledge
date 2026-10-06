


<p align="center">
  <img src="Assets/AppIcon-256.png" width="128" height="128" alt="Ledge app icon">
</p>

<h1 align="center">Ledge</h1>

<p align="center">
  A native, local-only slide-over web panel, notepad, and terminal for macOS.
</p>

Ledge keeps the sites you use most, your plain-text notes, and your shell one
hover or hotkey away. Open sites keep their WebKit sessions, and open terminals
keep their shells, while you switch tabs or hide the panel.

No server. No account. No telemetry. One open-source runtime dependency:
[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), which draws the
terminals.

> [!NOTE]
> Ledge is not yet signed with an Apple Developer ID, so downloads are unsigned
> and macOS asks for an extra confirmation on first launch. There is no
> automatic updater.

https://github.com/user-attachments/assets/cc7fc85f-4968-4e58-8821-4fec0083e260

## Download

Download the latest `Ledge-<version>.dmg` from
[Releases](https://github.com/brucez001/ledge/releases), open it, and drag Ledge
to Applications.

Because the build is unsigned, macOS blocks it the first time you open it:

1. Open Ledge. macOS shows **"Ledge" Not Opened** and says it could not verify
   the app. Click **Done**. Do not click *Move to Trash*, even though it is the
   highlighted button.
2. Go to **System Settings → Privacy & Security**.
3. Scroll down to the message naming Ledge and click **Open Anyway**.
4. Open Ledge again and confirm when prompted.

You only need to do this once. macOS shows this warning for any app that has not
been signed with an Apple Developer certificate. These steps will be removed once
I obtain one. Building from source following the steps below also avoids them.

## Features

- **Edge panel** — docks to the left or right edge. Reveal it by hovering
  there, resize it, or pin it open. Edge hover can be turned off.
- **Sites** — keep favourites on Home; open sites keep their sessions.
- **Notes** — Markdown notes, styled as you type, with a rendered preview.
  Saved on your Mac as plain files.
- **Terminals** — your login shell in a tab. Split it into panes, each with a
  title bar and a **✕** to close it.
- **Restored at launch** — the sidebar comes back after a restart, and a
  restored site or terminal loads only when you select it.

## Requirements

- macOS 14 Sonoma or later
- Xcode 16 or later

Xcode 26 and later install the Metal compiler separately, and SwiftTerm needs it
to build. Install it once if needed:

```zsh
xcodebuild -downloadComponent MetalToolchain
```

## Build and run

```zsh
git clone https://github.com/brucez001/ledge.git
cd ledge
Scripts/build-local-app.sh --install --open
```

This builds a release app, installs it at `~/Applications/Ledge.app`, and
launches it.

To build without installing:

```zsh
Scripts/build-local-app.sh --open
```

The bundle is written to `build/Ledge.app`.

Use the app-bundle build for normal use and for bundle-only behaviour such as
launch at login and website camera or microphone permissions.

## Privacy

Ledge has no backend, account system, analytics, advertising, payments,
licensing, or update service.

Network traffic is limited to websites you open and favicon requests. Site
icons are requested from the site first; unresolved icons may use Google's
favicon service by default. Choose **Site only** or **Letter tiles only** in
Privacy settings to disable that fallback.

Website data is stored by macOS WebKit. Favourites and preferences stay in
`UserDefaults`, and favicon data is cached in Application Support.
Notes are saved as plain-text files under Application Support and never leave
your Mac.

Terminals run your own login shell on your Mac, with your permissions. Ledge
keeps no record of what you type or what a terminal prints; to rebuild the
sidebar it remembers only how each open terminal is split and each pane's
working directory.

Ledge is intentionally a focused edge browser, not a cloud-synced workspace or
notification platform.

## Development

```zsh
swift run
swift build
swift test
Scripts/dev-check.sh
Scripts/dev-check.sh --build-only
Scripts/generate-app-icon.sh
```

See [`AGENTS.md`](AGENTS.md) for project conventions and behavioural contracts.

## Licence

Ledge's source code and original assets are available under the
[MIT Licence](LICENSE). Copyright © 2026 Bruce Zhu.

SwiftTerm is available under the MIT Licence; see
[`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md), which is also included in
the app.
