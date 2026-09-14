# ClipChum

A small native clipboard manager that lives in the macOS menu bar.

- Remembers the last **M** clips (default 500) and shows the last **N** (default 10) when opened.
- Typed clips with type-aware rows: plain text, rich text (RTF/HTML), images, file references, links.
- Search across every kept clip (SQLite FTS5, prefix matching).
- Files are stored as references (path + bookmark that follows renames/moves). Optionally
  *dereference* them: copy the bytes into a content-addressed blob folder so the clip still
  pastes after the original is gone. Image bytes are kept by default (thumbnail always).
- Settings: N, M, which kinds to record, size caps, excluded apps, hotkey, paste-back,
  launch at login.
- Respects `org.nspasteboard.ConcealedType` / `TransientType` (password managers).

## Build and run

Requires Xcode 26 / Swift 6.

```bash
make run            # swift build -c release → build/ClipChum.app → ~/Applications, then open
make test           # swift test (core library: parser, store, ingester)
make toggle         # open/close the panel from a script (Darwin notification)
make settings       # open the settings window from a script
```

If dependency resolution fails because git rewrites GitHub HTTPS URLs to SSH, resolve once with
`GIT_CONFIG_GLOBAL=/dev/null swift package resolve`.

The bundle is ad-hoc signed by default. macOS ties the Accessibility grant (needed only for
"paste directly") to the code signature, so it is re-asked after every rebuild. To avoid that,
create a self-signed code-signing certificate named `ClipChum Dev` in Keychain Access and build
with `make run SIGN_IDENTITY="ClipChum Dev"`.

## Using it

- Click the clipboard icon in the menu bar, or press **⌘⇧V** (configurable), to open the panel.
  It opens without stealing focus from the app you are in.
- Type to search. **↑/↓** select, **↩** copies (and pastes if enabled), **Esc** clears/closes,
  **⌘⌫** deletes, **⌘P** pins, **⌘,** opens settings. Right-click a row for more.
- Right-click the menu bar icon for Settings and Quit.

## Layout

```
Sources/ClipChumCore   # no UI: Clip model, PasteboardParser, ClipStore (GRDB+FTS5),
                       # BlobStore, FileReference, Ingester, Settings
Sources/ClipChum       # AppDelegate, PasteboardMonitor, ClipPanel (non-activating NSPanel),
                       # ClipListView/ClipRowView (SwiftUI), SettingsView, PasteService
Tests/ClipChumCoreTests
Support/Info.plist     # LSUIElement=true (no Dock icon)
```

Data lives in `~/Library/Application Support/ClipChum/` (`clipchum.sqlite` + `Blobs/`, the
latter excluded from Spotlight).

## How capture works

macOS has no pasteboard-change notification. `PasteboardMonitor` polls
`NSPasteboard.general.changeCount` (default every 0.4 s, configurable); the read is a single
integer, so the cost is negligible. Copies that land inside one interval are collapsed to the
latest one.
