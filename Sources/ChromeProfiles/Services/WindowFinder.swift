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

    /// Match Chromium-style window titles. Chrome/Brave both use "page - Profile" patterns.
    private static func titleMatches(_ title: String, profile name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let separators = [" - ", " — ", " – "]
        for sep in separators {
            let suffix = "\(sep)\(name)"
            if title.hasSuffix(suffix) { return true }
        }
        return title == name
    }

    static func pid(of window: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(window, &p)
        return p
    }

    /// Find the window we can *confidently* attribute to the given profile (scans only this
    /// profile's browser). On macOS this is only possible in two cases:
    ///   1. Title-suffix match — the browser put the profile name in the window title. Some
    ///      Brave/Chromium setups do this; default Chrome on macOS does NOT (the title is just
    ///      the active tab's page title), so this rarely fires for Chrome.
    ///   2. A single lone window AND lsof confirms *this* profile is the one running. Guarding
    ///      on `isActive` is essential: without it, clicking a *closed* profile while a different
    ///      profile owns the only window would focus the wrong account. Covers Brave / single-
    ///      profile Chrome, which omit the profile from the title.
    /// Returns nil when several profiles' windows coexist with no profile in their titles —
    /// the Accessibility API cannot tell them apart (they share one PID), so the caller must
    /// fall back to relaunching with `--profile-directory`.
    static func window(forProfile profile: ChromeProfile) -> AXUIElement? {
        let candidates = [profile.displayName, profile.givenName ?? ""].filter { !$0.isEmpty }
        var allWindows: [AXUIElement] = []
        for app in runningApps(for: profile.browser) {
            for w in windows(of: app.processIdentifier) {
                guard let title = axTitle(of: w) else { continue }
                for name in candidates where titleMatches(title, profile: name) {
                    return w
                }
                allWindows.append(w)
            }
        }
        if allWindows.count == 1, BrowserActivity.isActive(profile) { return allWindows[0] }
        return nil
    }

    /// Build a map of profile.id → AXUIElement for the given profiles.
    static func allWindowsMappedToProfiles(_ profiles: [ChromeProfile]) -> [String: AXUIElement] {
        var out: [String: AXUIElement] = [:]
        // browser -> nameToProfileId
        var browserIndex: [Browser: [String: String]] = [:]
        var browserProfiles: [Browser: [ChromeProfile]] = [:]
        for p in profiles {
            var idx = browserIndex[p.browser] ?? [:]
            idx[p.displayName] = p.id
            if let g = p.givenName, !g.isEmpty, idx[g] == nil { idx[g] = p.id }
            browserIndex[p.browser] = idx
            browserProfiles[p.browser, default: []].append(p)
        }
        var unmatchedByBrowser: [Browser: [AXUIElement]] = [:]
        for (browser, app) in allBrowserApps(Set(browserIndex.keys)) {
            guard let idx = browserIndex[browser] else { continue }
            for w in windows(of: app.processIdentifier) {
                guard let title = axTitle(of: w) else { continue }
                var matched = false
                for (name, pid) in idx where titleMatches(title, profile: name) {
                    if out[pid] == nil { out[pid] = w }
                    matched = true
                    break
                }
                if !matched {
                    unmatchedByBrowser[browser, default: []].append(w)
                }
            }
        }
        // Fallback: per-browser, if exactly one window unmatched and exactly one profile of that browser
        // is unmapped, pair them. Handles Brave (no profile name in title) for the common single-profile case.
        for (browser, unmatched) in unmatchedByBrowser where unmatched.count == 1 {
            let profilesOfBrowser = browserProfiles[browser] ?? []
            let unmapped = profilesOfBrowser.filter { out[$0.id] == nil }
            if unmapped.count == 1 {
                out[unmapped[0].id] = unmatched[0]
            }
        }
        return out
    }

    /// Debug helper.
    static func allBrowserTitles(_ browsers: Set<Browser> = Set(Browser.allCases)) -> [String] {
        allBrowserApps(browsers).flatMap { (_, app) in
            windows(of: app.processIdentifier).compactMap(axTitle)
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
