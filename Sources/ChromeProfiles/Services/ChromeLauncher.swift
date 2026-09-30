import Foundation
import AppKit
import ApplicationServices

enum ChromeLauncher {
    /// Spawn a new browser window with the given profile.
    static func launch(profile: ChromeProfile, url: String? = nil, incognito: Bool = false) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        var args = ["-na", profile.browser.appName, "--args", "--profile-directory=\(profile.dirName)"]
        if incognito { args.append("--incognito") }
        if let url, !url.isEmpty, isSafeURL(url) {
            args.append("--")   // end-of-options: stop Chromium parsing the URL as a switch
            args.append(url)
        }
        task.arguments = args
        do { try task.run() } catch {
            NSLog("ChromeLauncher launch failed: \(error)")
        }
    }

    /// Only forward web/file URLs to the browser, and never a value that could be parsed as a
    /// command-line switch. Combined with the `--` end-of-options token in `launch`, this prevents
    /// a pasted "--switch" from altering the browser's launch flags (Chromium switch-injection).
    private static func isSafeURL(_ url: String) -> Bool {
        guard !url.hasPrefix("-") else { return false }
        guard let scheme = URL(string: url)?.scheme?.lowercased() else { return false }
        return ["http", "https", "file", "chrome", "brave"].contains(scheme)
    }

    /// If a window for this profile already exists, focus it.
    /// Otherwise spawn a new one. If url given, opens that URL in the chosen profile.
    /// `profiles` is every known profile: telling this profile's windows apart needs its siblings.
    static func launchOrFocus(profile: ChromeProfile, among profiles: [ChromeProfile],
                              url: String? = nil, incognito: Bool = false) {
        if incognito {
            // Always spawn a new incognito window; never focus existing
            launch(profile: profile, url: url, incognito: true)
            return
        }
        if let url, !url.isEmpty {
            // URLs can contain sensitive query strings or tokens; never write them to logs.
            NSLog("[Polychrome] open dropped URL in \(profile.id)")
            launch(profile: profile, url: url)
            return
        }
        // Window detection runs AX enumeration and possibly a synchronous `lsof`, which can block
        // for hundreds of ms. Run it off the main thread so a profile click never freezes the UI;
        // hop back to the main actor for the AppKit/AX activation.
        Task.detached(priority: .userInitiated) {
            switch WindowFinder.focusTarget(for: profile, among: profiles) {
            case .window(let win):
                NSLog("[Polychrome] focus existing window for \(profile.id)")
                await MainActor.run { WindowFinder.focus(win) }
            case .browser:
                // Live in a title-opaque browser (Brave, single-profile Chrome) whose several
                // windows can't be told apart: land on what's already open, not a duplicate.
                NSLog("[Polychrome] \(profile.id) running but window unidentifiable; activating \(profile.browser.displayName) rather than relaunching")
                await MainActor.run { WindowFinder.activate(profile.browser) }
            case .noWindow:
                // A bare `open --profile-directory` is a no-op once the browser is running, so
                // `launch` uses `open -na`, which reliably surfaces the profile in a new window.
                NSLog("[Polychrome] no window for \(profile.id); surfacing profile via relaunch")
                await MainActor.run { launch(profile: profile) }
            }
        }
    }

    static func launchMany(profiles: [ChromeProfile], among all: [ChromeProfile]) {
        for p in profiles { launchOrFocus(profile: p, among: all) }
    }
}
