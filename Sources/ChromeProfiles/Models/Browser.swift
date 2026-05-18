import Foundation
import AppKit

/// Supported Chromium-based browsers. Adding more is one entry.
enum Browser: String, Codable, CaseIterable, Identifiable, Hashable {
    case chrome
    case brave

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .brave:  return "Brave"
        }
    }

    /// Used in `open -na` and AppleScript-style invocation.
    var appName: String {
        switch self {
        case .chrome: return "Google Chrome"
        case .brave:  return "Brave Browser"
        }
    }

    /// Bundle identifier of the running app (for AX window enumeration).
    var bundleID: String {
        switch self {
        case .chrome: return "com.google.Chrome"
        case .brave:  return "com.brave.Browser"
        }
    }

    /// Root directory containing the `Local State` file + profile dirs.
    var dataDir: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .chrome:
            return home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
        case .brave:
            return home.appendingPathComponent("Library/Application Support/BraveSoftware/Brave-Browser", isDirectory: true)
        }
    }

    var localStateURL: URL { dataDir.appendingPathComponent("Local State") }

    /// `Local State` exists for this browser on disk.
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: localStateURL.path)
    }

    /// SF Symbol glyph for the browser. Falls back if the named symbol is unavailable.
    var symbolName: String {
        switch self {
        case .chrome: return "globe"
        case .brave:  return "shield.lefthalf.filled"
        }
    }

    var accent: NSColor {
        switch self {
        case .chrome: return NSColor.systemBlue
        case .brave:  return NSColor.systemOrange
        }
    }
}
