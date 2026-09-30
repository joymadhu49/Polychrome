import Foundation
import AppKit
import ApplicationServices

/// Maps browser windows to profiles. Every caller — the menu's open state and window
/// list, focusing a profile, closing its windows, tiling — goes through `snapshot`, so
/// they all agree on which window belongs to whom.
enum WindowFinder {
    private static func runningApps(for browser: Browser) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID)
    }

    private static func windows(of pid: pid_t) -> [AXUIElement] {
        let axApp = AXUIElementCreateApplication(pid)
        var raw: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &raw)
        guard err == .success, let arr = raw as? [AXUIElement] else { return [] }
        return arr
    }

    static func axTitle(of window: AXUIElement) -> String? {
        var raw: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &raw)
        return raw as? String
    }

    // MARK: title parsing (pure)

    /// Chrome/Chromium append the active profile to the macOS *Accessibility* window title
    /// whenever more than one profile has been used (AppleScript hides this; AX does not):
    ///   "<page title> - <App> - <givenName>"                        e.g. "... - Google Chrome - Sumaiya"
    ///   "<page title> - <App> - <givenName> (<profile name>)"       e.g. "... - Google Chrome - Joy (JOY_M)"
    /// where <App> is `browser.displayName` ("Google Chrome" / "Brave"). Returns the text after
    /// the marker ("Sumaiya", "Joy (JOY_M)"); `matchProfile` interprets it.
    ///
    /// Returns nil when the marker is absent — single-profile browsers (Brave, or Chrome with one
    /// profile) omit it. Uses the LAST (`.backwards`) marker occurrence so a page title that itself
    /// contains " - Google Chrome - " can't fool the parser.
    static func profileToken(from title: String, appLabel: String) -> String? {
        // Chrome uses " - " (ASCII hyphen) on English systems; tolerate em/en-dash locale variants.
        for sep in [" - ", " — ", " – "] {
            let marker = "\(sep)\(appLabel)\(sep)"
            guard let r = title.range(of: marker, options: .backwards) else { continue }
            let token = String(title[r.upperBound...])
            if !token.isEmpty { return token }
        }
        return nil
    }

    /// Every way to read a token as "<given> (<name>)", longest name first. A profile name can
    /// itself contain parentheses ("Joy (Joy (Work))"), so a single split can't be trusted.
    static func parentheticalNames(in token: String) -> [String] {
        guard token.hasSuffix(")") else { return [] }
        let close = token.index(before: token.endIndex)
        var names: [String] = []
        var searchStart = token.startIndex
        while let r = token.range(of: " (", range: searchStart..<token.endIndex) {
            if r.lowerBound > token.startIndex, r.upperBound < close {
                names.append(String(token[r.upperBound..<close]))
            }
            searchStart = r.upperBound
        }
        return names
    }

    /// The profile a title token names, or nil when it names none of `profiles`.
    ///   1. The whole token is a profile name — Chrome omits the parenthetical when the name equals
    ///      the given name, and a name like "Work (old)" must not be split.
    ///   2. "<given> (<name>)" — the parenthetical is the profile name. Matching the given name here
    ///      instead would let a profile grab a sibling's window that merely shares a given name.
    ///   3. A bare given name that exactly one profile carries.
    static func matchProfile(token: String, in profiles: [ChromeProfile]) -> ChromeProfile? {
        if let p = profiles.first(where: { $0.displayName == token }) { return p }
        let names = parentheticalNames(in: token)
        for name in names {
            if let p = profiles.first(where: { $0.displayName == name }) { return p }
        }
        guard names.isEmpty else { return nil }
        let byGiven = profiles.filter { $0.givenName?.isEmpty == false && $0.givenName == token }
        return byGiven.count == 1 ? byGiven[0] : nil
    }

    /// Which of one browser's windows belong to which profile, from their titles alone.
    struct TitleAttribution: Equatable {
        /// profile.id → indices into the titles, in enumeration order.
        var indicesByProfileID: [String: [Int]] = [:]
        /// Indices no profile can be sure of.
        var unattributed: [Int] = []
        /// Windows whose title carried a profile marker, known profile or not. Non-zero means the
        /// browser is "title-transparent": every normal window names its profile, so a profile
        /// without a matching title has no window, whatever lsof says.
        var tokenWindowCount = 0
    }

    /// Pure attribution over one browser's window titles; `profiles` must be every known profile
    /// of that browser (others are ignored), not just the ones the caller cares about.
    ///   • A title naming a profile goes to that profile.
    ///   • A title naming a profile we don't know stays unattributed — it's never handed to some
    ///     other profile that happens to have no window.
    ///   • Untokened titles (incognito, DevTools, app windows in a multi-profile browser) stay
    ///     unattributed — except in a title-opaque browser with a single profile, where every
    ///     window can only be that profile's.
    static func attribute(titles: [String], browser: Browser, profiles: [ChromeProfile]) -> TitleAttribution {
        let own = profiles.filter { $0.browser == browser }
        var out = TitleAttribution()
        var untokened: [Int] = []
        for (i, title) in titles.enumerated() {
            guard let token = profileToken(from: title, appLabel: browser.displayName) else {
                untokened.append(i)
                continue
            }
            out.tokenWindowCount += 1
            if let p = matchProfile(token: token, in: own) {
                out.indicesByProfileID[p.id, default: []].append(i)
            } else {
                out.unattributed.append(i)
            }
        }
        if out.tokenWindowCount == 0, own.count == 1, !untokened.isEmpty {
            out.indicesByProfileID[own[0].id] = untokened
        } else {
            out.unattributed = (out.unattributed + untokened).sorted()
        }
        return out
    }

    /// The AX title with the browser's trailing marker removed, for display in menus:
    ///   "GitHub - Google Chrome - Joy (JOY_M)" → "GitHub"
    ///   "GitHub - Brave"                       → "GitHub"
    /// Falls back to the raw title when no marker is present.
    static func pageTitle(from title: String, appLabel: String) -> String {
        for sep in [" - ", " — ", " – "] {
            if let r = title.range(of: "\(sep)\(appLabel)\(sep)", options: .backwards) {
                let page = String(title[..<r.lowerBound])
                if !page.isEmpty { return page }
            }
            let suffix = "\(sep)\(appLabel)"
            if title.hasSuffix(suffix) {
                let page = String(title.dropLast(suffix.count))
                if !page.isEmpty { return page }
            }
        }
        return title
    }

    // MARK: scanning

    static func pid(of window: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(window, &p)
        return p
    }

    /// One open window: the raw AX handle plus a menu-ready page title (browser/profile
    /// marker stripped). Order follows AX enumeration.
    struct ProfileWindow {
        let element: AXUIElement
        let title: String
    }

    /// Snapshot of every scanned browser's windows.
    struct WindowScan {
        /// profile.id → every window attributed to it. The first is the one to focus.
        var windowsByProfileID: [String: [ProfileWindow]] = [:]
        /// browser → titled windows no profile could claim.
        var unattributed: [Browser: [ProfileWindow]] = [:]
        /// browser → total AX window count of its running process(es).
        var windowCount: [Browser: Int] = [:]
        /// browser → windows whose title carried a profile marker (see `TitleAttribution`).
        var tokenWindowCount: [Browser: Int] = [:]

        /// Titles don't name profiles (Brave, single-profile Chrome), so lsof has to help.
        func isTitleOpaque(_ browser: Browser) -> Bool { (tokenWindowCount[browser] ?? 0) == 0 }

        /// A title-opaque browser with several profiles can't say whose its windows are. Its lone
        /// window is a profile's only when lsof reports that profile as the browser's ONE live
        /// profile: Chrome keeps a closed profile's files open for a long time, so "this profile
        /// is active" alone can't tell its window from a sibling's.
        mutating func applyActivity(_ activeDirs: Set<String>, browser: Browser, profiles: [ChromeProfile]) {
            guard isTitleOpaque(browser), windowCount[browser] == 1, activeDirs.count == 1,
                  let lone = unattributed[browser], lone.count == 1,
                  let owner = profiles.first(where: { $0.browser == browser && activeDirs.contains($0.dirName) }),
                  windowsByProfileID[owner.id] == nil else { return }
            windowsByProfileID[owner.id] = lone
            unattributed[browser] = nil
        }
    }

    /// Scan the running browsers of `profiles` and attribute their windows from titles alone.
    /// Pass every known profile, not a subset (see `attribute`). Synchronous AX IPC — call off
    /// the main thread.
    static func scanWindows(_ profiles: [ChromeProfile]) -> WindowScan {
        var scan = WindowScan()
        for (browser, own) in Dictionary(grouping: profiles, by: \.browser) {
            var titles: [String] = []
            var titled: [ProfileWindow] = []
            for app in runningApps(for: browser) {
                let ws = windows(of: app.processIdentifier)
                scan.windowCount[browser, default: 0] += ws.count
                for w in ws {
                    guard let title = axTitle(of: w) else { continue }
                    titles.append(title)
                    titled.append(ProfileWindow(element: w, title: pageTitle(from: title, appLabel: browser.displayName)))
                }
            }
            let a = attribute(titles: titles, browser: browser, profiles: own)
            scan.tokenWindowCount[browser] = a.tokenWindowCount
            for (id, indices) in a.indicesByProfileID {
                scan.windowsByProfileID[id] = indices.map { titled[$0] }
            }
            if !a.unattributed.isEmpty {
                scan.unattributed[browser] = a.unattributed.map { titled[$0] }
            }
        }
        return scan
    }

    struct Snapshot {
        var scan: WindowScan
        /// browser → profile dirs lsof reports live. Only present where lsof was needed: every
        /// browser without AX access, else title-opaque browsers with windows and several profiles.
        var activeDirs: [Browser: Set<String>]
    }

    /// Window scan plus the lsof fallback, wherever titles can't answer on their own. Pass every
    /// known profile. Synchronous AX IPC and `lsof` — call off the main thread.
    static func snapshot(_ profiles: [ChromeProfile], axTrusted: Bool = true) -> Snapshot {
        var scan = axTrusted ? scanWindows(profiles) : WindowScan()
        var active: [Browser: Set<String>] = [:]
        for (browser, own) in Dictionary(grouping: profiles, by: \.browser) {
            if axTrusted {
                // Titles name every window, or a lone profile owns them all: lsof adds nothing.
                // No windows: nothing is open, whatever background process lingers.
                guard scan.isTitleOpaque(browser), (scan.windowCount[browser] ?? 0) > 0, own.count > 1 else { continue }
            }
            let dirs = BrowserActivity.activeDirs(for: browser, knownDirs: Set(own.map(\.dirName)))
            active[browser] = dirs
            if axTrusted { scan.applyActivity(dirs, browser: browser, profiles: own) }
        }
        return Snapshot(scan: scan, activeDirs: active)
    }

    private static func browserSiblings(of profile: ChromeProfile, in profiles: [ChromeProfile]) -> [ChromeProfile] {
        var own = profiles.filter { $0.browser == profile.browser }
        if !own.contains(where: { $0.id == profile.id }) { own.append(profile) }
        return own
    }

    enum FocusTarget {
        /// A window we can confidently tie to the profile.
        case window(AXUIElement)
        /// The profile is live in a title-opaque browser whose windows can't be told apart:
        /// bring the browser forward rather than spawn a duplicate window.
        case browser
        /// The profile has no window.
        case noWindow
    }

    /// Where clicking `profile` should land. `profiles` is every known profile — attribution needs
    /// the profile's siblings to rule their windows out. Call off the main thread.
    static func focusTarget(for profile: ChromeProfile, among profiles: [ChromeProfile]) -> FocusTarget {
        let snap = snapshot(browserSiblings(of: profile, in: profiles))
        if let w = snap.scan.windowsByProfileID[profile.id]?.first { return .window(w.element) }
        // `activeDirs` only exists for title-opaque browsers that have windows. Where titles name
        // profiles, no matching title means no window — lsof's lingering file handles don't count.
        if snap.activeDirs[profile.browser]?.contains(profile.dirName) == true { return .browser }
        return .noWindow
    }

    /// Every window attributed to the profile — the same set the menu lists for it. Call off the
    /// main thread.
    static func windows(forProfile profile: ChromeProfile, among profiles: [ChromeProfile]) -> [AXUIElement] {
        let snap = snapshot(browserSiblings(of: profile, in: profiles))
        return (snap.scan.windowsByProfileID[profile.id] ?? []).map(\.element)
    }

    // MARK: actions

    /// Close a window by pressing its AX close button — equivalent to clicking the red
    /// traffic light, so Chrome runs its normal teardown (session save, beforeunload).
    static func close(_ window: AXUIElement) {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXCloseButtonAttribute as CFString, &raw) == .success,
              let raw, CFGetTypeID(raw) == AXUIElementGetTypeID() else { return }
        let button = raw as! AXUIElement
        AXUIElementPerformAction(button, kAXPressAction as CFString)
    }

    /// Bring the browser's existing windows to the front without spawning a new one.
    static func activate(_ browser: Browser) {
        for app in runningApps(for: browser) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// OFF by default. Set the env var `POLYCHROME_AXDUMP=1` before launching the (AX-granted) app
    /// to log, per Chrome/Brave window, the AX window title plus a depth-limited dump of every
    /// descendant's role/title/description/roleDescription. Lets the lead confirm exactly what
    /// Chrome exposes via AX without changing production behaviour. Runs entirely off the main
    /// thread; `kAXChildrenAttribute` reads are synchronous IPC to Chrome and can block, so the
    /// descent is capped at `maxDepth` (children-only, no AXParent walking).
    static func debugDumpAXIfEnabled(maxDepth: Int = 4) {
        guard ProcessInfo.processInfo.environment["POLYCHROME_AXDUMP"] == "1" else { return }
        Task.detached(priority: .utility) {
            // Defined inside the detached task (not captured from outside) so they don't
            // need @Sendable — capturing local functions across a concurrency boundary
            // is an error in Swift 6.
            func attr(_ el: AXUIElement, _ a: String) -> String {
                var raw: CFTypeRef?
                AXUIElementCopyAttributeValue(el, a as CFString, &raw)
                return (raw as? String) ?? ""
            }
            func children(_ el: AXUIElement) -> [AXUIElement] {
                var raw: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &raw)
                return (raw as? [AXUIElement]) ?? []
            }
            func walk(_ el: AXUIElement, _ depth: Int) {
                let pad = String(repeating: "  ", count: depth)
                NSLog("[AXDUMP]\(pad)[\(attr(el, kAXRoleAttribute as String))] rd='\(attr(el, kAXRoleDescriptionAttribute as String))' title='\(attr(el, kAXTitleAttribute as String))' desc='\(attr(el, kAXDescriptionAttribute as String))'")
                if depth < maxDepth { for c in children(el) { walk(c, depth + 1) } }
            }
            for b in Browser.allCases {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: b.bundleID) {
                    for (i, w) in windows(of: app.processIdentifier).enumerated() {
                        NSLog("[AXDUMP] ==== \(b.displayName) WIN[\(i)] title='\(axTitle(of: w) ?? "")' ====")
                        for c in children(w) { walk(c, 1) }
                    }
                }
            }
        }
    }

    static func focus(_ window: AXUIElement) {
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        // Make it the app's main + focused window BEFORE activating: when the app
        // comes forward it then surfaces THIS window, not its last key window —
        // essential when several windows of the same Chrome process are open.
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let p = pid(of: window)
        if let app = NSRunningApplication(processIdentifier: p) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        // Activation is asynchronous, and Chromium sometimes re-promotes its previous
        // key window while becoming active — a second main+raise shortly after wins
        // that race deterministically.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
            AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        }
    }
}
