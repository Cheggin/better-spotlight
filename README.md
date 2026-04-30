# Better Spotlight

A macOS Spotlight replacement that bundles Gmail, Google Calendar, and scoped local file
search behind a single keyboard shortcut: **press both Shift keys at the same time**.

Liquid-glass UI inspired by Apple's Spotlight, two-pane layout with a calendar/event
detail on the right.

## Build

Requires macOS 14+, full Xcode 15+, and [`task`](https://taskfile.dev), `xcodegen`, `xcbeautify`:

```bash
brew install go-task xcodegen xcbeautify
task up      # generates project, builds, launches the app
task lint    # typechecks every Swift source against the macOS SDK
```

`task up` is everything you need — regenerates the Xcode project, builds Debug, and opens the .app. For signing-required runs, open the project in Xcode once and set your team in Signing & Capabilities.

## First-run setup

1. The app runs as an `LSUIElement` (no Dock icon, no menu bar by default — there's a
   small status item with a Settings menu).
2. Open Settings, sign in with Google (browser opens, PKCE OAuth flow).
3. Add folders to "Searchable folders" (e.g. `~/Documents`, `~/Downloads`,
   `~/Desktop`). The file provider scopes `NSMetadataQuery` to these.
4. Press both shifts simultaneously to summon the panel.

## Hotkey notes

`NSEvent.addGlobalMonitorForEvents` is used for `.flagsChanged` events. macOS may
prompt for **Accessibility** permission the first time — grant it under
System Settings → Privacy & Security → Accessibility.

## Secrets

`BetterSpotlight/Secrets.swift` holds the OAuth client ID and is gitignored. A
template lives at `Secrets.swift.example`.

## Project layout

See `reagan_plan_better_spotlight.md`.
