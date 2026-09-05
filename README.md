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
> Ledge is not yet signed with an Apple Developer ID, so downloads are unsigned
> and macOS asks for an extra confirmation on first launch. There is no
> automatic updater.

https://github.com/user-attachments/assets/0009b609-aa19-4cfa-9a0a-4fc8e9552779

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

- Dock the panel on the left or right edge of your Mac.
- Reveal it with edge hover or **⇧⌘Space**.
- Resize the panel to suit your workflow.
- Keep the panel open persistently when you need it.
- Turn off reveal on edge hover when it becomes annoying.
- Save favourite sites for quick access.
- Take a quick note with **⌘N** — it opens as a tab beside your sessions and
  saves locally as a plain Markdown file.
- Write in Markdown with a formatting toolbar, and swap between the rendered
  preview and the raw text with **⇧⌘P**.
- See your Markdown as you type it: “- ” becomes a bullet dot point, “# ” a
  heading, “**bold**” bold. The markers themselves stop being drawn once you
  move on, and reappear on the line you are editing. The file stays plain
  text — only the drawing changes. Turn it off with **⇧⌘L** or in Notes
  settings to write against the raw characters.
- Rename a note by clicking its title — the name is the note's own, so renaming
  never rewrites your Markdown and a heading you type never renames the note.
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
Notes are saved as plain-text files under Application Support and never leave
your Mac.

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
