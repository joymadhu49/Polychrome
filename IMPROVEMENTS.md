# Polychrome — Improvement Tracker

A living document for watching how Polychrome improves over time. Each entry is a
concrete, checkable item: check it off (with the PR/commit that shipped it) rather
than deleting it, so the history of improvements stays visible.

**How to use this doc**

1. When you notice a bug, rough edge, or idea — add it under the right priority.
2. When you fix one — tick the box and note the version/PR.
3. Before cutting a release, skim *High priority* to decide what's next.

CI now builds every push and pull request (`.github/workflows/ci.yml`), so a green
check on a PR means the app still compiles and bundles — the baseline for every
item below.

---

## Shipped

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

## High priority

- [ ] **Unit tests for the pure logic.** `WindowTiler.frames` (geometry math),
  the AX title parser (`WindowFinder.profileToken` — needs to become internal
  or move to a testable type), profile sorting in `ChromeProfileLoader`, and
  `HotkeyConfig.displayString` are all pure functions begging for a test target
  in `Package.swift`. Run them in the CI job (`swift test`).
- [ ] **Localized-Chrome window detection.** Profile matching parses the English
  AX title format (`"<page> - Google Chrome - <name>"`). On non-English systems
  the app-name label or separator may differ, silently degrading everyone to the
  lone-window fallback. Needs a report from a localized system (run with
  `POLYCHROME_AXDUMP=1`) and, likely, a more tolerant parser.
- [ ] **Reduce `lsof` cost.** While the menu is open, title-opaque browsers
  (Brave, single-profile Chrome) trigger a synchronous `lsof` every 2.5 s
  refresh. On machines with many open files this can take hundreds of ms of a
  background thread and burn CPU. Consider caching results between refreshes,
  scanning only when window count changes, or a cheaper signal.

## Medium priority

- [ ] **More Chromium browsers.** `Browser` was designed so adding one is a
  single enum entry: Edge, Vivaldi, Arc, Opera, and vanilla Chromium are the
  obvious candidates. Needs each browser's `dataDir`, bundle ID, and app name.
- [ ] **Number-key launch.** With the menu open, ⌘1–⌘9 should open/focus the
  Nth visible profile — the keyboard-first flow stops one step short today.
- [ ] **Auto-update.** Ship Sparkle (or a lightweight update check against the
  GitHub Releases feed) so users get fixes without manually re-downloading the
  DMG.
- [ ] **Homebrew cask** (`brew install --cask polychrome`) once releases are
  stable — the notarized DMG already satisfies cask requirements.
- [ ] **Menu list rendering scalability.** Each row computes
  `visibleOrdered.firstIndex(of:)` for keyboard-focus highlighting — O(n²) per
  render. Invisible at ~10 profiles; worth precomputing an index map if users
  with 30+ profiles show up.

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
