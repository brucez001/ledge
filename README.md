<p align="center">
  <img src="Assets/AppIcon-256.png" width="128" height="128" alt="Ledge app icon">
</p>

<h1 align="center">Ledge</h1>

<p align="center">
  A native, local-only slide-over web panel for macOS.
</p>

Ledge keeps the web apps you use most one hover or hotkey away. Open sites keep
their WebKit sessions while you switch sites or hide the panel.

No server. No account. No telemetry. No third-party runtime dependencies.

> [!NOTE]
> Ledge is currently distributed as source code. There is no signed download or
> automatic updater.

## Demo

https://github.com/user-attachments/assets/3896ddec-94e9-4f65-928d-9d827cd870df

## Features

- Dock the panel on the left or right edge of your Mac.
- Reveal it with edge hover or **⇧⌘Space**.
- Resize the panel to suit your workflow.
- Keep the panel open persistently when you need it.
- Turn off reveal on edge hover when it becomes annoying.
- Save favourite sites for quick access.
- Use keyboard shortcuts for quick access and navigation.

## Requirements

- macOS 14 Sonoma or later
- Swift 6 and the Xcode command-line tools

Install the command-line tools if needed:

```zsh
xcode-select --install
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
