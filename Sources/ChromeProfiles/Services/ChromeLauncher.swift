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

    /// Back-compat for tiler: directory + browser.
    static func launch(profileDir: String, browser: Browser, url: String? = nil, incognito: Bool = false) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        var args = ["-na", browser.appName, "--args", "--profile-directory=\(profileDir)"]
        if incognito { args.append("--incognito") }
        if let url, !url.isEmpty, isSafeURL(url) {
            args.append("--")
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
        return ["http", "https", "file", "chrome"].contains(scheme)
    }

    /// If a window for this profile already exists, focus it.
    /// Otherwise spawn a new one. If url given, opens that URL in the chosen profile.
    static func launchOrFocus(profile: ChromeProfile, url: String? = nil, incognito: Bool = false) {
        if incognito {
            // Always spawn a new incognito window; never focus existing
            launch(profile: profile, url: url, incognito: true)
            return
        }
        if let url, !url.isEmpty {
            NSLog("[Polychrome] open URL in \(profile.id): \(url)")
            launch(profile: profile, url: url)
            return
        }
        // Window detection runs AX enumeration and a synchronous `lsof`, which can block for
        // hundreds of ms. Run it off the main thread so a profile click never freezes the UI;
        // hop back to the main actor for the AppKit/AX activation.
        Task.detached(priority: .userInitiated) {
            // 1) Focus an existing window only when we can confidently tie it to this profile
            //    (title carries the profile name, or a lone window confirmed active via lsof).
            if let win = WindowFinder.window(forProfile: profile) {
                NSLog("[Polychrome] focus existing window for \(profile.id)")
                await MainActor.run { WindowFinder.focus(win) }
                return
            }
            // 2) Can't identify the window. This is the normal case for Chrome with several
            //    profiles open: macOS Chrome keeps the profile name out of the window title and
            //    every window shares one process, so the Accessibility API cannot distinguish
            //    one profile's window from another's. Re-launching with --profile-directory is
            //    the only reliable way to bring this exact profile to the front — Chrome routes
            //    the request to its running instance and surfaces a window for that profile.
            //    (A bare `open --profile-directory` with no URL is a no-op once Chrome is
            //    running, so `launch` uses `open -na`, which reliably surfaces the profile.)
            NSLog("[Polychrome] no identifiable window for \(profile.id); surfacing profile via relaunch")
            await MainActor.run { launch(profile: profile) }
        }
    }

    static func launchMany(profiles: [ChromeProfile], url: String? = nil, incognito: Bool = false) {
        for p in profiles { launchOrFocus(profile: p, url: url, incognito: incognito) }
    }
}
