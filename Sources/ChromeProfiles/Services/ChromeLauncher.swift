import Foundation
import AppKit
import ApplicationServices

enum ChromeLauncher {
    /// Spawn a new Chrome window with the given profile.
    static func launch(profileDir: String, url: String? = nil) {
        let task = Process()
        task.launchPath = "/usr/bin/open"
        var args = ["-na", "Google Chrome", "--args", "--profile-directory=\(profileDir)"]
        if let url, !url.isEmpty { args.append(url) }
        task.arguments = args
        do { try task.run() } catch {
            NSLog("ChromeLauncher launch failed: \(error)")
        }
    }

    /// If a Chrome window for this profile already exists, focus it.
    /// Otherwise spawn a new one.
    static func launchOrFocus(profile: ChromeProfile) {
        if let win = WindowFinder.window(forProfile: profile) {
            NSLog("[Polychrome] focus existing window for \(profile.dirName) (\(profile.displayName))")
            WindowFinder.focus(win)
            return
        }
        NSLog("[Polychrome] no existing window for \(profile.dirName) (\(profile.displayName)); launching")
        launch(profileDir: profile.dirName)
    }

    static func launchMany(profiles: [ChromeProfile]) {
        for p in profiles { launchOrFocus(profile: p) }
    }
}
