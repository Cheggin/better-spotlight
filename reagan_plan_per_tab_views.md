# Per-tab center/right views

The current build uses one center pane (calendar grid) and one right pane (event detail) regardless of which tab is active. This plan replaces that with a per-tab layout switch.

## Architecture

`RootView` already owns `category` state. Add a `TabContentRouter` that returns the `(centerView, rightView)` pair for the current tab. Each tab's two views become small files under `UI/Tabs/<Tab>/`. Selection state per tab (selected event, selected message, selected file, selected contact, selected month-cell) lives in a `@StateObject TabState` so switching back to a tab restores its context.

## Per-tab plan

| Tab          | Center                                                  | Right                                                              | Notes                                                                                      |
|--------------|---------------------------------------------------------|--------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| **All**      | Empty / lightweight (today's agenda + recents)          | Detail of selected result (current behavior)                        | Keep existing behavior — Spotlight-style overview.                                          |
| **Messages** | Threaded conversation view (all messages w/ contact)    | Contact info card (name, handle, recent activity, "Open in Messages") | Group rows by `chat.db` thread, show last 100 messages w/ scroll. SMS / iMessage tinting.  |
| **Files**    | QuickLook preview (`QLPreviewView`) of selected file    | Metadata: path, size, modified, kind, tags, "Open in Finder", "Reveal" | Already have thumbnails — upgrade to full QuickLook for PDFs/images/videos.                 |
| **Folders**  | Two-column file browser inside the folder (Miller view) | File metadata (same as Files)                                      | Replace blank pane: clicking a folder shows its contents column-by-column.                 |
| **Calendar** | **Full month grid like Google Calendar** (image #39)    | Event detail (existing)                                            | Stack events per day in colored pills; clicking a pill = select event; clicking a cell = open `EventComposer` modal seeded for that day. |
| **Contacts** | Contact info card (editable: name, phone, email, etc.)  | Recent interactions: phone, SMS, FaceTime, email                   | Read+write via `CNContactStore`. Recent interactions: query `chat.db` + `CallHistory.storedata` (also Full Disk Access). |

## What to do about Folders

The cleanest UX is a Miller-column file browser: each click on a folder pushes a new column to the right, like Finder's column view. Right pane shows metadata for whatever's selected in the deepest column.

Less code path: just show a flat scrollable list of contents in the center, keep the right pane as file metadata. Identical to Files in mechanics but rooted at the selected folder rather than search results. Recommend starting here, upgrading to columns later.

## Calendar full month grid

What's needed:
- 7-column × 5-row grid filling the entire center pane
- Each cell shows the day number plus up to 4 stacked event pills colored by calendar
- Pills truncate (`9am Gym - Browser Use`) and overflow shows `+ N more`
- Multi-day events render as a single bar spanning multiple cells
- Click a pill → set `selectedID` → right pane shows `EventDetailView`
- Click a cell (empty area) → open `EventComposer` modal seeded with that date
- Header: `< Today >` + `Month YYYY` + view switcher (Day / Week / Month)
- Use the existing `CalendarAPI.events.list` for a wider window (full month ± 1 week)

Mechanics:
- New file `UI/Tabs/Calendar/MonthGrid.swift` — pure SwiftUI `LazyVGrid(columns: 7)`
- New file `UI/Tabs/Calendar/MultiDayBars.swift` — separate render pass for events spanning >1 day, drawn as absolute-positioned bars over the grid cells using a `GeometryReader`
- Existing `EventComposer` already handles new events; pass it the day's start as `initialStart`

## Contacts (read + write)

`CNContactStore` supports:
- `enumerateContacts(with:)` — read all contacts
- `executeSave(_:)` with `CNSaveRequest` — create / update / delete

Editing UX:
- Center is a vertical form: photo, name, phone numbers (multi-row), emails (multi-row), birthday, addresses
- Inline edits stage into a `CNMutableContact`, "Save" button writes via `CNSaveRequest.update(_:)`
- Right pane is a chronological feed: most-recent SMS exchange, missed calls, FaceTime, last email — all queried locally

Recent interactions sources:
- **Messages**: `~/Library/Messages/chat.db` — already integrated. Query rows where `handle.id` matches any of the contact's phones/emails.
- **Calls / FaceTime**: `~/Library/Application Support/CallHistoryDB/CallHistory.storedata` (SQLite). Schema is `ZCALLRECORD` with `ZADDRESS`, `ZSERVICE_PROVIDER` (telephony / FaceTime / FaceTimeAudio), `ZDATE` (Apple-epoch). Same Full Disk Access requirement.
- **Email**: query Gmail API with `from:<email> OR to:<email>` (already plumbed).

## Hotkey reliability

Switch from the current `flagsChanged` dual-Cmd monitor to Carbon `RegisterEventHotKey` with **⌃⌥⌘ + Space** (hyper-Space). Rock-solid registration, never coalesced by Cocoa, never intercepted by other apps. The dual-Cmd UX was a fun idea but `addGlobalMonitorForEvents(matching: .flagsChanged)` is fundamentally lossy — Apple drops events when our app isn't frontmost.

## Implementation order

1. `TabContentRouter` skeleton + per-tab `TabState`. (Small refactor.)
2. **Hotkey** swap to Carbon. (1 file change, fixes the "spam to make it open" bug.)
3. **Calendar month grid** — biggest visual win, isolates the work.
4. **Files** QuickLook preview + Folders Miller view.
5. **Messages** thread view (extend the existing `MessagesProvider` to fetch full thread by handle).
6. **Contacts** — center form + recent-interactions feed.

Each step is independent and shippable.
