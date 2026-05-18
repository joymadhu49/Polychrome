import Foundation
import AppKit

/// Detects which profile dirs a Chromium-based browser currently has open by
/// scanning open files via `lsof`. This is needed because Brave (and Chrome
/// with a single profile) omit the profile name from window titles, so AX-based
/// title matching fails. Each running profile holds files open inside its
/// `<profile-dir>/` subdirectory, which lsof reliably exposes.
enum BrowserActivity {
    /// Returns the subset of `knownDirs` whose directories are currently held
    /// open by any process of the given browser.
    static func activeDirs(for browser: Browser, knownDirs: Set<String>) -> Set<String> {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID)
        guard !apps.isEmpty, !knownDirs.isEmpty else { return [] }
        let pidArg = apps.map { String($0.processIdentifier) }.joined(separator: ",")

        let task = Process()
        task.launchPath = "/usr/sbin/lsof"
        task.arguments = ["-p", pidArg]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        do {
            try task.run()
        } catch {
            NSLog("[Polychrome] BrowserActivity: lsof launch failed: \(error)")
            return []
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let out = String(data: data, encoding: .utf8) ?? ""

        let prefix = browser.dataDir.path + "/"
        var dirs = Set<String>()
        for rawLine in out.split(separator: "\n") {
            guard let r = rawLine.range(of: prefix) else { continue }
            let after = rawLine[r.upperBound...]
            guard let slashIdx = after.firstIndex(of: "/") else { continue }
            let dirName = String(after[..<slashIdx])
            if knownDirs.contains(dirName) { dirs.insert(dirName) }
            if dirs.count == knownDirs.count { break }
        }
        return dirs
    }

    /// Convenience: is this profile's dir currently open?
    static func isActive(_ profile: ChromeProfile) -> Bool {
        activeDirs(for: profile.browser, knownDirs: [profile.dirName]).contains(profile.dirName)
    }

    /// AX main window of the first running instance of this browser, if any.
    static func mainWindow(for browser: Browser) -> AXUIElement? {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID) {
            let axApp = AXUIElementCreateApplication(app.processIdentifier)
            var raw: CFTypeRef?
            let err = AXUIElementCopyAttributeValue(axApp, kAXMainWindowAttribute as CFString, &raw)
            if err == .success, let v = raw, CFGetTypeID(v) == AXUIElementGetTypeID() {
                return (v as! AXUIElement)
            }
            // Fallback: first window from kAXWindowsAttribute
            var rawWins: CFTypeRef?
            let err2 = AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &rawWins)
            if err2 == .success, let arr = rawWins as? [AXUIElement], let w = arr.first {
                return w
            }
        }
        return nil
    }

    /// Bring the browser app to front. Works without AX permission.
    static func activateApp(_ browser: Browser) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID).first {
            if #available(macOS 14.0, *) {
                app.activate()
            } else {
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }
}
