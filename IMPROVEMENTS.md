# Polychrome — Improvement Tracker

A living document for watching how Polychrome improves over time. Each entry is a
concrete, checkable item: check it off (with the PR/commit that shipped it) rather
than deleting it, so the history of improvements stays visible.

**How to use this doc**

1. When you notice a bug, rough edge, or idea — add it under the right priority.
2. When you fix one — tick the box and note the version/PR.
3. Before cutting a release, skim *High priority* to decide what's next.

CI now tests and builds every push and pull request (`.github/workflows/ci.yml`),
so a green check on a PR means the app's regression suite passes and it still
compiles and bundles — the baseline for every item below.

---

## Shipped

- [x] **One window→profile rule set for the whole app** — the menu, focusing, closing and
  tiling each attributed windows their own way and disagreed. All now go through
  `WindowFinder.snapshot`, with the title rules as a pure, unit-tested function
  (`WindowAttributionTests`). Fixes three wrong-window bugs: (post-v1.5.0)
  - clicking a closed profile could focus a *different* profile's lone window, because
    Chrome keeps a closed profile's files open and lsof called it "active" — lsof no longer
    overrides browsers whose titles name their profiles;
  - tiling A + B while an unselected profile C had one window moved C's window into B's slot
    instead of launching B — windows are now attributed against every profile, and a window
    naming someone else is never handed to a closed profile;
  - "Close N Windows" did nothing in Brave / single-profile Chrome with 2+ windows — it now
    closes exactly the windows the row lists.
- [x] **Tiling waits for cold launches** — launched windows were given ~2 s to appear, so a
  cold Chrome start usually tiled without them. Now up to 10 s (ends as soon as all appear);
  title-opaque browsers pair windows that appeared after launching with the launched
  profiles; minimized windows are restored first; frames are set size → position → size so
  moves between displays land exactly; all AX work is off the main thread. (post-v1.5.0)
- [x] **Launch at login reflects reality** — the toggle was a stored flag that stayed "on"
  after a failed registration or a change in System Settings; it now mirrors
  `SMAppService`, and shows when macOS is waiting for approval in Login Items. (post-v1.5.0)
- [x] **Global shortcuts can't hijack typing** — Shift alone (⇧A, ⇧`) is rejected at record
  time except on F-keys; the recorder says what's missing. Saved shortcuts keep working.
  (post-v1.5.0)
- [x] **Smaller fixes** (post-v1.5.0): profile names containing parentheses ("Work (old)")
  now match their windows; ⌘1–⌘9 use physical keys so they work on AZERTY and other
  layouts; "Main display" means the display with the menu bar, not wherever the menu was;
  `lsof` runs with `-n -P -Fn` (no DNS lookups) and is skipped for single-profile browsers;
  the menu's live-refresh timer no longer restarts on every render; the first open no
  longer reloads twice; dead URL-era code removed.

- [x] **Auto-updates via Sparkle** — daily check against the appcast attached to the
  newest GitHub release; every DMG is EdDSA-signed in CI and verified before install.
  Scheduled updates found mid-work show as a quiet "Update available" row in the menu
  (Sparkle gentle reminders) instead of an alert stealing focus. Settings → General has
  the toggles; the release job refuses to run if `CFBundleVersion` wasn't bumped.
  (v1.5.0)
- [x] **Universal binary** — releases were arm64-only, so Polychrome couldn't launch on
  the Intel Macs that macOS 13 still supports. CI now asserts both slices. (v1.5.0)
- [x] **Staple the app, not just the DMG** — the copy in /Applications had no ticket of
  its own, so first launch needed Apple's servers. Notarization is now two-pass. (v1.5.0)
- [x] **No more blank "Polychrome Settings" window** — the SwiftUI `App` lifecycle's
  placeholder `Settings { EmptyView() }` scene opened as an empty window at launch.
  Replaced with a plain AppKit entry point and a hidden Edit menu so ⌘C/⌘V still work.
  (v1.5.0)
- [x] **Redesigned menu** — search is the header; one shared mouse/keyboard highlight;
  presence dot on the avatar; browser headers/badges only when 2+ browsers have
  profiles; multi-select moved into the footer, which becomes a Cancel / Open / Tile bar;
  window boxes only when there's more than one window; ⚙︎ menu with Settings, Check for
  Updates, Refresh, About, Quit. (v1.5.0)
- [x] **Number-key launch** — ⌘1–⌘9 open the first nine profiles; hold ⌘ to reveal the
  numbers. Also ⌘, ⌘R, ⌘Q inside the menu. (v1.5.0)
- [x] **Redesigned Settings** — native grouped Form (System Settings style), 7 panes incl.
  About; visual layout cards; removed the outdated "Polychrome is ad-hoc signed" copy.
  (v1.5.0)
- [x] **Theme override reaches the menu** — the popover inherited the menu bar's
  appearance (wallpaper-driven), so Light/Dark in Settings only affected the Settings
  window. (v1.5.0)
- [x] **Settings layout preview drew off-screen** — it ran mock rects through the
  primary-display Y flip. Geometry is now split into a pure `frames(for:in:CGRect,…)`
  used by previews and tests. (v1.5.0)
- [x] **Display picker blank** when the saved display is disconnected — now shows the
  main-display fallback tiling actually uses. (v1.5.0)
- [x] **O(n²) row rendering** — rows looked up their index with a linear search each
  render; now one index map per render, and list + keyboard nav share one section model.
  (v1.5.0)
- [x] **Reliable shifted-symbol hotkeys** — recording `Shift + \`` now displays
  the typed `~` while preserving the physical Carbon binding, with the same
  treatment for other shifted punctuation. Conflicting shortcuts are no longer
  silently saved as active: Polychrome restores the prior binding, explains the
  failure, and offers Retry. Regression tests now run in CI. (v1.4.7)
- [x] **Styled DMG installer** — the install window now has a designed
  backdrop with one native San Francisco type system, icon-and-label cards,
  a Polychrome gradient drag arrow, positioned icons, a volume icon, and a
  hidden app extension. The Retina asset is generated with AppKit
  (scripts/make-dmg-background.swift); plain hdiutil remains as fallback so
  releases can't break. (v1.4.4, refined post-v1.4.4)
- [x] **Cleaner, more professional menu** — removed the URL-history chips from
  under the search field, removed URL entry/history entirely, and a drag
  hovering a profile row shows a clear accent "Open here" badge with a
  stronger highlight. Links now open only through direct profile-row drops and
  are neither displayed nor retained. (post-v1.4.4)
- [x] **Fully automatic releases** — merging to `main` with a bumped
  `CFBundleShortVersionString` auto-builds, signs, notarizes, tags, and
  publishes the release with the DMG. A cheap Linux pre-job skips the macOS
  build when the version already has a tag. No manual steps remain. (v1.4.2)
- [x] **Drag & drop links onto profiles** — drag a URL (or selected text that
  looks like one) over the menubar icon and the menu opens mid-drag; drop it on
  any profile row to open it in that profile. Rows highlight with an "Open
  here" hint while targeted. (v1.4.0, simplified post-v1.4.4)
- [x] **Drag & drop hardening** — the icon's drag-catcher is pinned with Auto
  Layout (a bounds-sized frame could be zero before the status item laid out,
  leaving the icon deaf to drags); row drop targets moved outside the row
  Button so its hit-testing can never shadow them; and a drop released on the
  icon itself originally held the URL for a later profile selection; that
  fallback was removed when direct row drops became the only URL path. (v1.4.2,
  simplified post-v1.4.4)
- [x] **Close a profile's window from the menu** — open profiles show an ✕ on
  hover that closes their window(s) via the AX close button, so Chrome runs its
  normal teardown. (v1.3.4)
- [x] **Cut releases from the Actions tab** — `release.yml` accepts a manual
  dispatch with `release_tag`/`target_commitish`, so a signed + notarized
  release can be published without terminal access to push a tag. (v1.3.4)
- [x] **CI build on every push/PR** — previously nothing compiled the code until a
  release tag was pushed, so a broken commit could sit on `main` unnoticed.
  (v1.3.3)
- [x] **Fix Split-V tiling layout** — `Split vertical` produced side-by-side
  columns (duplicating *Row*) instead of the top/bottom split its name and icon
  promise, and ignored the "First pane size" slider that Settings shows for it.
  It now tiles a top pane sized by the slider with the remaining windows in an
  even row beneath — the mirror of Split-H. *Smart* mode's 2-window case keeps
  its old even side-by-side behavior (now via *Row*, identical frames). (v1.3.3)
- [x] **Quick-launch accepts `brave://` URLs** — the URL safety filter allowed
  `chrome://` but rejected Brave's equivalent scheme. (v1.3.3)
- [x] **Accurate layout names** — "Split horizontal (2 only)" claimed a 2-window
  limit that hasn't been true since the right-pane stacking landed. (v1.3.3)
- [x] **Fix build on current Swift toolchains** — caught by the new CI on its
  first run: `DisplayInfo` declared `Hashable` but `CGRect` members can't
  synthesize it (now hashed manually), and `WindowFinder`'s debug-dump helpers
  were captured across a concurrency boundary (an error under Swift 6). (v1.3.3)

## High priority

- [ ] **Hotkey-opened menu doesn't get keyboard focus.** Under macOS 14+'s cooperative
  activation, `NSApp.activate(ignoringOtherApps:)` is ignored, so when the menu opens via
  the global hotkey the previous app (e.g. Chrome) stays frontmost and receives typing,
  ↑/↓, ↩ and ⌘1–9. Clicking the menubar icon works. Fix: host the menu in a
  non-activating `NSPanel` (how Raycast/Alfred/Spotlight do it) instead of `NSPopover`.
  Present in 1.4.x too.
- [ ] **More unit tests for the pure logic.** `WindowTiler.frames`
  (`WindowTilerFramesTests`), the AX title parser and window attribution
  (`WindowAttributionTests`) and `HotkeyConfig.displayString` (`HotkeyConfigTests`) are
  covered; still missing: profile sorting in `ChromeProfileLoader` (needs the `sorted`
  helper to become internal).
- [ ] **Localized-Chrome window detection.** Profile matching parses the English
  AX title format (`"<page> - Google Chrome - <name>"`). On non-English systems
  the app-name label or separator may differ, silently degrading everyone to the
  lone-window fallback. Needs a report from a localized system (run with
  `POLYCHROME_AXDUMP=1`) and, likely, a more tolerant parser.
- [ ] **Reduce `lsof` cost.** While the menu is open, title-opaque browsers
  (Brave, single-profile Chrome) trigger a synchronous `lsof` every 2.5 s
  refresh. On machines with many open files this can take hundreds of ms of a
  background thread and burn CPU. Consider caching results between refreshes,
  scanning only when window count changes, or a cheaper signal. (Partly done: lsof now
  skips DNS/port lookups and only runs for title-opaque browsers with 2+ profiles.)

## Medium priority

- [ ] **More Chromium browsers.** `Browser` was designed so adding one is a
  single enum entry: Edge, Vivaldi, Arc, Opera, and vanilla Chromium are the
  obvious candidates. Needs each browser's `dataDir`, bundle ID, and app name.
- [ ] **Homebrew cask** (`brew install --cask polychrome`) once releases are
  stable — the notarized DMG already satisfies cask requirements.
- [ ] **Delta updates.** `generate_appcast` can produce binary deltas between
  releases; the DMG is small today, so full downloads are fine for now.

## Low priority / ideas

- [ ] Per-profile custom hotkeys (e.g. ⌘⇧1 always opens "Work").
- [ ] Bulk action: "Open all profiles tagged *Work*".
- [ ] Export / import settings (tags, layout, hotkey) as JSON.
- [ ] UI localization.
- [ ] Remember and restore a named window arrangement ("workspace").
- [ ] Optional window-frame animation when tiling.

## Known limitations (tracked, not currently planned)

- Profile detection requires the browser at its standard install path.
- Window→profile mapping depends on Chrome exposing profile names in AX titles
  (multi-profile Chrome does; Brave and single-profile Chrome rely on the
  `lsof` fallback).
