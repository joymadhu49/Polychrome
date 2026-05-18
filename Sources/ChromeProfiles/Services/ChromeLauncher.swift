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
        if let url, !url.isEmpty { args.append(url) }
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
        if let url, !url.isEmpty { args.append(url) }
        task.arguments = args
        do { try task.run() } catch {
            NSLog("ChromeLauncher launch failed: \(error)")
        }
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
        // 1) AX title match (works for Chrome multi-profile, Brave 2+ profiles).
        if let win = WindowFinder.window(forProfile: profile) {
            NSLog("[Polychrome] focus existing window for \(profile.id) by AX title")
            WindowFinder.focus(win)
            return
        }
        // 2) lsof fallback (Brave with single profile, or any browser whose
        //    window titles don't include the profile name).
        if BrowserActivity.isActive(profile) {
            NSLog("[Polychrome] \(profile.id) is active per lsof; activating browser")
            if let win = BrowserActivity.mainWindow(for: profile.browser) {
                WindowFinder.focus(win)
            } else {
                BrowserActivity.activateApp(profile.browser)
            }
            return
        }
        // 3) Nothing matched — spawn a new window.
        NSLog("[Polychrome] no existing window for \(profile.id); launching")
        launch(profile: profile)
    }

    static func launchMany(profiles: [ChromeProfile], url: String? = nil, incognito: Bool = false) {
        for p in profiles { launchOrFocus(profile: p, url: url, incognito: incognito) }
    }
}
