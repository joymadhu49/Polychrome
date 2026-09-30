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
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // -n/-P: never resolve socket addresses or port names (DNS lookups made this slow).
        // -Fn: machine-readable output with just the file names we parse, not full rows.
        task.arguments = ["-n", "-P", "-Fn", "-p", pidArg]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        // Nothing reads stderr, and a full pipe would block lsof forever.
        task.standardError = FileHandle.nullDevice
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
}
