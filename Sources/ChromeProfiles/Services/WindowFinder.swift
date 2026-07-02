import Foundation
import AppKit
import ApplicationServices

enum WindowFinder {
    private static func runningApps(for browser: Browser) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID)
    }

    private static func allBrowserApps(_ browsers: Set<Browser> = Set(Browser.allCases)) -> [(Browser, NSRunningApplication)] {
        var out: [(Browser, NSRunningApplication)] = []
        for b in browsers {
            for app in runningApps(for: b) { out.append((b, app)) }
        }
        return out
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

    /// Chrome/Chromium append the active profile to the macOS *Accessibility* window title
    /// whenever more than one profile has been used (AppleScript hides this; AX does not):
    ///   "<page title> - <App> - <givenName>"                        e.g. "... - Google Chrome - Sumaiya"
    ///   "<page title> - <App> - <givenName> (<profile name>)"       e.g. "... - Google Chrome - Joy (JOY_M)"
    /// where <App> is `browser.displayName` ("Google Chrome" / "Brave"). The givenName maps to
    /// `ChromeProfile.givenName` and the parenthetical to `ChromeProfile.displayName`.
    ///
    /// Returns nil when the marker is absent — single-profile browsers (Brave, or Chrome with one
    /// profile) omit it, and those are covered by the lone-window + lsof fallback instead.
    /// Uses the LAST (`.backwards`) marker occurrence so a page title that itself contains
    /// " - Google Chrome - " can't fool the parser.
    private static func profileToken(from title: String, appLabel: String) -> (given: String, name: String?)? {
        // Chrome uses " - " (ASCII hyphen) on English systems; tolerate em/en-dash locale variants.
        for sep in [" - ", " — ", " – "] {
            let marker = "\(sep)\(appLabel)\(sep)"
            guard let r = title.range(of: marker, options: .backwards) else { continue }
            var token = String(title[r.upperBound...])
            var name: String?
            if token.hasSuffix(")"), let open = token.range(of: " (", options: .backwards) {
                let inner = token[token.index(open.lowerBound, offsetBy: 2)..<token.index(before: token.endIndex)]
                name = String(inner)
                token = String(token[..<open.lowerBound])
            }
            guard !token.isEmpty else { continue }
            return (token, name.flatMap { $0.isEmpty ? nil : $0 })
        }
        return nil
    }

    /// True when the AX window `title` belongs to `profile`, by parsing Chrome's profile token.
    private static func titleMatches(_ title: String, profile: ChromeProfile) -> Bool {
        guard let tok = profileToken(from: title, appLabel: profile.browser.displayName) else { return false }
        // A parenthetical ("Joy (JOY_M)") appears iff Chrome's profile name differs from the gaia
        // given name; require it to equal THIS profile's displayName. Matching the given name when a
        // parenthetical is present would let a profile grab a sibling window that merely shares a
        // given name, focusing the wrong account.
        if let n = tok.name { return n == profile.displayName }
        // No parenthetical iff name == given name, so the token is both — match displayName exactly.
        return tok.given == profile.displayName
    }

    static func pid(of window: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(window, &p)
        return p
    }

    /// Find the window we can *confidently* attribute to the given profile (scans only this
    /// profile's browser). On macOS this works in two cases:
    ///   1. AX-title profile-token match — Chrome/Chromium append the profile to the *Accessibility*
    ///      window title once more than one profile has been used (see `profileToken`). This is the
    ///      common, reliable case for multi-profile Chrome and is the one that was previously broken.
    ///   2. A single lone window AND lsof confirms *this* profile is the one running. Guarding
    ///      on `isActive` is essential: without it, clicking a *closed* profile while a different
    ///      profile owns the only window would focus the wrong account. Covers Brave / single-
    ///      profile Chrome, which omit the profile from the title.
    /// Returns nil when several profiles' windows coexist and none carry an identifiable profile
    /// token (e.g. a non-English Chrome whose title format differs), so the caller can fall back to
    /// relaunching with `--profile-directory`.
    static func window(forProfile profile: ChromeProfile) -> AXUIElement? {
        var allWindows: [AXUIElement] = []
        for app in runningApps(for: profile.browser) {
            for w in windows(of: app.processIdentifier) {
                guard let title = axTitle(of: w) else { continue }
                if titleMatches(title, profile: profile) { return w }
                allWindows.append(w)
            }
        }
        if allWindows.count == 1, BrowserActivity.isActive(profile) { return allWindows[0] }
        return nil
    }

    /// Per-browser snapshot of currently open windows.
    struct WindowScan {
        /// profile.id → a window we could attribute to it (title-token match, or the
        /// lone-window fallback for opaque single-profile browsers).
        var windowByProfileID: [String: AXUIElement] = [:]
        /// browser → total AX window count of its running process(es).
        var windowCount: [Browser: Int] = [:]
        /// browser → number of windows matched via an actual profile token in the title.
        /// Zero means the browser is "title-opaque" (Brave / single-profile Chrome omit
        /// the profile from AX titles); >0 means "title-transparent" (Chrome multi-profile,
        /// where AX alone can identify every open window and lsof is unnecessary).
        var tokenMatchCount: [Browser: Int] = [:]
    }

    /// Scan every running browser's windows and attribute them to profiles where possible.
    static func scanWindows(_ profiles: [ChromeProfile]) -> WindowScan {
        var scan = WindowScan()
        var browserProfiles: [Browser: [ChromeProfile]] = [:]
        for p in profiles { browserProfiles[p.browser, default: []].append(p) }

        var unmatchedByBrowser: [Browser: [AXUIElement]] = [:]
        for (browser, app) in allBrowserApps(Set(browserProfiles.keys)) {
            let profilesOfBrowser = browserProfiles[browser] ?? []
            let ws = windows(of: app.processIdentifier)
            scan.windowCount[browser, default: 0] += ws.count
            for w in ws {
                guard let title = axTitle(of: w) else { continue }
                // Prefer a parenthetical display-name match over a given-name match so two profiles
                // that share a given name (e.g. "Joy (JOY_M)" vs "Joy (Personal)") don't collide.
                guard let tok = profileToken(from: title, appLabel: browser.displayName) else {
                    unmatchedByBrowser[browser, default: []].append(w)
                    continue
                }
                let byName = tok.name.flatMap { n in profilesOfBrowser.first { $0.displayName == n } }
                let match = byName
                    ?? profilesOfBrowser.first { p in (p.givenName.map { !$0.isEmpty && tok.given == $0 } ?? false) }
                    ?? profilesOfBrowser.first { $0.displayName == tok.given }
                if let p = match {
                    scan.tokenMatchCount[browser, default: 0] += 1
                    if scan.windowByProfileID[p.id] == nil { scan.windowByProfileID[p.id] = w }
                } else {
                    unmatchedByBrowser[browser, default: []].append(w)
                }
            }
        }
        // Fallback: per-browser, if exactly one window is unmatched and exactly one profile of that
        // browser is still unmapped, pair them. Handles Brave / single-profile Chrome (no profile
        // token in the title) for the common single-profile case.
        for (browser, unmatched) in unmatchedByBrowser where unmatched.count == 1 {
            let profilesOfBrowser = browserProfiles[browser] ?? []
            let unmapped = profilesOfBrowser.filter { scan.windowByProfileID[$0.id] == nil }
            if unmapped.count == 1 {
                scan.windowByProfileID[unmapped[0].id] = unmatched[0]
            }
        }
        return scan
    }

    /// Build a map of profile.id → AXUIElement for the given profiles.
    static func allWindowsMappedToProfiles(_ profiles: [ChromeProfile]) -> [String: AXUIElement] {
        scanWindows(profiles).windowByProfileID
    }

    /// True when the browser has at least one on-screen window. Lets callers tell an
    /// "active" profile (per lsof) that actually has a window from one that's merely a
    /// background process holding files open.
    static func hasWindows(_ browser: Browser) -> Bool {
        for app in runningApps(for: browser) where !windows(of: app.processIdentifier).isEmpty {
            return true
        }
        return false
    }

    /// Bring the browser's existing windows to the front without spawning a new one.
    static func activate(_ browser: Browser) {
        for app in runningApps(for: browser) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Debug helper.
    static func allBrowserTitles(_ browsers: Set<Browser> = Set(Browser.allCases)) -> [String] {
        allBrowserApps(browsers).flatMap { (_, app) in
            windows(of: app.processIdentifier).compactMap(axTitle)
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
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        let p = pid(of: window)
        if let app = NSRunningApplication(processIdentifier: p) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
