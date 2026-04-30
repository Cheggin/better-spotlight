# Better Spotlight — Plan

A macOS Spotlight replacement with Gmail + Google Calendar + scoped file search, activated by pressing **both Shift keys simultaneously**. Liquid-glass aesthetic matching the reference screenshots.

## Stack

- **Swift 5.10 / SwiftUI + AppKit** (for `NSPanel`, global hotkey, `.accessory` activation)
- **Xcode project generated via `xcodegen`** (so the repo stays a flat tree of source files, not a binary `pbxproj`)
- **Google APIs**: Gmail v1 + Calendar v3 via REST (no GoogleSignIn pod — manual OAuth 2.0 with PKCE through `ASWebAuthenticationSession`)
- **File search**: `NSMetadataQuery` (Spotlight's own backend) scoped to user-configured folder list
- **Hotkey**: Carbon `RegisterEventHotKey` is single-key only, so we use `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` and detect both shift modifiers active in the same flag-change event

## Architecture

```
BetterSpotlight/
├── App/
│   ├── BetterSpotlightApp.swift          # @main, sets .accessory, owns AppDelegate
│   ├── AppDelegate.swift                 # status item, hotkey monitor, panel lifecycle
│   └── SpotlightPanel.swift              # NSPanel subclass (floating, borderless, .nonactivating)
├── Hotkey/
│   └── DualShiftMonitor.swift            # global flagsChanged monitor — fires when both shifts go down within 200ms
├── UI/
│   ├── RootView.swift                    # the full liquid-glass panel
│   ├── SearchBar.swift
│   ├── CategoryTabs.swift                # All · Files · Folders · Calendar · Mail · Messages · Contacts
│   ├── ResultsList.swift                 # left pane, grouped by category
│   ├── DetailPane.swift                  # right pane, switches on selection type
│   ├── CalendarMiniView.swift            # month grid for Calendar tab
│   ├── EventDetailView.swift             # right-pane event card (matches screenshot 2)
│   ├── BottomActionBar.swift
│   └── Theme/
│       ├── LiquidGlass.swift             # NSVisualEffectView wrapper + custom blur stack
│       └── Tokens.swift                  # spacing, radii, typography (NOT Inter)
├── Search/
│   ├── SearchCoordinator.swift           # debounced query → fans out to providers → merges + ranks
│   ├── Providers/
│   │   ├── SearchProvider.swift          # protocol
│   │   ├── FileProvider.swift            # NSMetadataQuery, scoped to user folders, fuzzy match
│   │   ├── GmailProvider.swift           # users.messages.list?q=...
│   │   ├── CalendarProvider.swift        # events.list?q=... + freebusy
│   │   └── FuzzyMatcher.swift            # subsequence + bonus scoring (no exact match — per global rules)
├── Google/
│   ├── OAuthClient.swift                 # PKCE flow via ASWebAuthenticationSession, Keychain token storage
│   ├── TokenStore.swift                  # SecItem wrapper
│   ├── GmailAPI.swift
│   └── CalendarAPI.swift
├── Settings/
│   └── SettingsView.swift                # pick searchable folders, sign in/out of Google
├── Resources/
│   ├── Info.plist
│   └── BetterSpotlight.entitlements      # NOT sandboxed (need full-disk metadata + global monitor)
└── Secrets.swift                         # gitignored — OAuth client id only (no secret, PKCE)

project.yml                               # xcodegen spec
.gitignore                                # ignores Secrets.swift, build/, .DS_Store, xcuserdata
README.md
```

## Hotkey detail

`NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` does NOT need accessibility permissions for modifier-only events on recent macOS. Logic:

1. On every flagsChanged event, read `event.modifierFlags.deviceIndependentFlagsMask` and the raw `CGEventFlags` to distinguish left vs right shift via `kCGEventFlagMaskShift` + `NX_DEVICELSHIFTKEYMASK` / `NX_DEVICERSHIFTKEYMASK`.
2. Track timestamps of left-shift-down and right-shift-down. If both are down with delta ≤ 200ms and no other modifier is active, toggle the panel.
3. Require both to release before the next trigger fires (prevents repeat).

If macOS later requires accessibility for this, prompt user with `AXIsProcessTrustedWithOptions`.

## OAuth detail

- Google "Desktop app" OAuth client → no client secret needed in practice; PKCE only.
- Loopback redirect: `http://127.0.0.1:<random-port>/callback` served by an in-process `NWListener`.
- Scopes: `https://www.googleapis.com/auth/gmail.readonly`, `https://www.googleapis.com/auth/gmail.send`, `https://www.googleapis.com/auth/calendar.readonly`, `https://www.googleapis.com/auth/calendar.events`.
- Tokens stored in Keychain under `com.reagan.betterspotlight.google`.
- Refresh-token flow on 401.

## Liquid-glass styling

- Root container: `NSVisualEffectView` with `.hudWindow` material + `.behindWindow` blending → already gives the frosted base.
- Layered on top: a thin `LinearGradient` overlay (white→clear at 6% opacity), 1px inner stroke at 18% white, outer drop shadow with very soft 60px radius and 2% opacity.
- Corner radius 22pt on the panel, 14pt on cards, 10pt on rows.
- Typography: SF Pro Display for headers (15/600), SF Pro Text for body (13/500). **No Inter.**
- No "sparkles" icon. No `!important`. No left outline borders. Reusable styles live in `UI/Theme/Tokens.swift` and `LiquidGlass.swift` (the global-CSS-equivalent).

## Search ranking

`FuzzyMatcher` uses subsequence matching with bonuses for: prefix match, word-boundary match, camelCase boundary, recent access. Per global rules: fuzzy, never exact.

## Build / run

```bash
brew install xcodegen
cd /Users/reagan/Documents/GitHub/better-spotlight
xcodegen
open BetterSpotlight.xcodeproj
# In Xcode: set signing team, Run (⌘R)
```

First launch:
1. Settings (gear in top-right of panel) → "Sign in with Google" → browser flow.
2. Settings → "Searchable folders" → add `~/Documents`, `~/Downloads`, etc.
3. Press both shifts to summon the panel.

## Build order (what I'm doing now)

1. `project.yml`, `.gitignore`, `Info.plist`, entitlements, `Secrets.swift.example`
2. App skeleton + panel + dual-shift hotkey (provable end-to-end)
3. Liquid-glass shell + search bar + tabs (visual parity with screenshots)
4. File provider with `NSMetadataQuery` (real local results)
5. Google OAuth + token store
6. Gmail + Calendar providers
7. Detail pane variants (event card, mail preview, file preview)
8. Mini calendar grid
9. Bottom action bar
10. Settings window
