import Foundation
import AppKit
import ApplicationServices

enum WindowFinder {
    static let chromeBundleID = "com.google.Chrome"

    private static func chromeApps() -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: chromeBundleID)
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

    /// Try several title-suffix variants Chrome uses across versions/locales.
    private static func titleMatches(_ title: String, profile name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let separators = [" - ", " — ", " – "]   // hyphen, em-dash, en-dash
        for sep in separators {
            let suffix = "\(sep)\(name)"
            if title.hasSuffix(suffix) { return true }
            // mid-title (e.g. "Page - Google Chrome - Joy - extra")
            if title.contains(suffix) { return true }
        }
        return title == name
    }

    static func pid(of window: AXUIElement) -> pid_t {
        var p: pid_t = 0
        AXUIElementGetPid(window, &p)
        return p
    }

    /// Find a Chrome window matching the given profile.
    static func window(forProfile profile: ChromeProfile) -> AXUIElement? {
        let candidates = [profile.displayName, profile.givenName ?? ""].filter { !$0.isEmpty }
        for app in chromeApps() {
            for w in windows(of: app.processIdentifier) {
                guard let title = axTitle(of: w) else { continue }
                for name in candidates where titleMatches(title, profile: name) {
                    return w
                }
            }
        }
        return nil
    }

    /// Back-compat helper used by ChromeLauncher.
    static func window(forProfileName name: String) -> AXUIElement? {
        for app in chromeApps() {
            for w in windows(of: app.processIdentifier) {
                guard let title = axTitle(of: w) else { continue }
                if titleMatches(title, profile: name) { return w }
            }
        }
        return nil
    }

    static func allWindowsMappedToProfiles(_ profiles: [ChromeProfile]) -> [String: AXUIElement] {
        var out: [String: AXUIElement] = [:]
        // Build lookup of (candidateName -> dirName)
        var nameToDir: [String: String] = [:]
        for p in profiles {
            nameToDir[p.displayName] = p.dirName
            if let g = p.givenName, !g.isEmpty, nameToDir[g] == nil {
                nameToDir[g] = p.dirName
            }
        }
        for app in chromeApps() {
            for w in windows(of: app.processIdentifier) {
                guard let title = axTitle(of: w) else { continue }
                for (name, dir) in nameToDir where titleMatches(title, profile: name) {
                    if out[dir] == nil { out[dir] = w }
                    break
                }
            }
        }
        return out
    }

    /// Debug helper.
    static func allChromeTitles() -> [String] {
        chromeApps().flatMap { app in
            windows(of: app.processIdentifier).compactMap(axTitle)
        }
    }

    static func focus(_ window: AXUIElement) {
        // Unminimize
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        // Raise window within app
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        // Activate Chrome app
        let p = pid(of: window)
        if let app = NSRunningApplication(processIdentifier: p) {
            app.activate(options: [.activateIgnoringOtherApps])
        }
        // Make this the focused window
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }
}
