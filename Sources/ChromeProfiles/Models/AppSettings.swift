import Foundation
import Combine
import AppKit

@MainActor
final class AppSettings: ObservableObject {
    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            LaunchAtLogin.set(enabled: launchAtLogin)
        }
    }

    @Published var showEmails: Bool {
        didSet { UserDefaults.standard.set(showEmails, forKey: "showEmails") }
    }

    @Published var focusExisting: Bool {
        didSet { UserDefaults.standard.set(focusExisting, forKey: "focusExisting") }
    }

    @Published var groupByStatus: Bool {
        didSet { UserDefaults.standard.set(groupByStatus, forKey: "groupByStatus") }
    }

    @Published var quickLaunchEnabled: Bool {
        didSet { UserDefaults.standard.set(quickLaunchEnabled, forKey: "quickLaunchEnabled") }
    }

    @Published var tagsEnabled: Bool {
        didSet { UserDefaults.standard.set(tagsEnabled, forKey: "tagsEnabled") }
    }

    @Published var showAXBanner: Bool {
        didSet { UserDefaults.standard.set(showAXBanner, forKey: "showAXBanner") }
    }

    @Published var groupByBrowser: Bool {
        didSet { UserDefaults.standard.set(groupByBrowser, forKey: "groupByBrowser") }
    }

    @Published var pinned: Bool {
        didSet { UserDefaults.standard.set(pinned, forKey: "pinMenuOnTop") }
    }

    @Published var enabledBrowsers: Set<Browser> {
        didSet {
            let raw = enabledBrowsers.map { $0.rawValue }
            UserDefaults.standard.set(raw, forKey: "enabledBrowsers")
        }
    }

    @Published var urlHistory: [String] {
        didSet {
            UserDefaults.standard.set(urlHistory, forKey: "urlHistory")
        }
    }

    static let urlHistoryLimit = 5

    func remember(url: String) {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return }
        var list = urlHistory.filter { $0 != u }
        list.insert(u, at: 0)
        if list.count > Self.urlHistoryLimit { list = Array(list.prefix(Self.urlHistoryLimit)) }
        urlHistory = list
    }

    func clearURLHistory() { urlHistory = [] }

    @Published var theme: ThemeOverride {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "theme")
            applyTheme()
        }
    }

    @Published var tagByDir: [String: String] {
        didSet {
            if let data = try? JSONEncoder().encode(tagByDir) {
                UserDefaults.standard.set(data, forKey: "tagByDir")
            }
        }
    }

    @Published var hotkey: HotkeyConfig {
        didSet {
            hotkey.save()
            HotkeyManager.shared.apply(hotkey)
        }
    }

    @Published var layout: LayoutConfig {
        didSet { layout.save() }
    }

    init() {
        let d = UserDefaults.standard
        self.launchAtLogin = d.bool(forKey: "launchAtLogin")
        self.showEmails = (d.object(forKey: "showEmails") as? Bool) ?? true
        self.focusExisting = (d.object(forKey: "focusExisting") as? Bool) ?? true
        self.groupByStatus = (d.object(forKey: "groupByStatus") as? Bool) ?? true
        self.quickLaunchEnabled = (d.object(forKey: "quickLaunchEnabled") as? Bool) ?? true
        self.tagsEnabled = (d.object(forKey: "tagsEnabled") as? Bool) ?? true
        self.showAXBanner = (d.object(forKey: "showAXBanner") as? Bool) ?? true
        self.groupByBrowser = (d.object(forKey: "groupByBrowser") as? Bool) ?? true
        self.pinned = d.bool(forKey: "pinMenuOnTop")
        let themeRaw = d.string(forKey: "theme") ?? ThemeOverride.system.rawValue
        self.theme = ThemeOverride(rawValue: themeRaw) ?? .system

        // Enabled browsers — default to installed ones.
        if let raw = d.stringArray(forKey: "enabledBrowsers") {
            self.enabledBrowsers = Set(raw.compactMap(Browser.init(rawValue:)))
        } else {
            let installed = Browser.allCases.filter { $0.isInstalled }
            self.enabledBrowsers = installed.isEmpty ? Set([.chrome]) : Set(installed)
        }

        // URL history
        self.urlHistory = d.stringArray(forKey: "urlHistory") ?? []

        // Tag map — with one-time migration from legacy bare-dir keys to "chrome:Dir" composite keys.
        if let data = d.data(forKey: "tagByDir"),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            if !d.bool(forKey: "tagByDirMigratedV2") && !map.isEmpty {
                var migrated: [String: String] = [:]
                for (k, v) in map {
                    if k.contains(":") { migrated[k] = v }
                    else { migrated["chrome:\(k)"] = v }
                }
                self.tagByDir = migrated
                if let enc = try? JSONEncoder().encode(migrated) {
                    d.set(enc, forKey: "tagByDir")
                }
                d.set(true, forKey: "tagByDirMigratedV2")
            } else {
                self.tagByDir = map
            }
        } else {
            self.tagByDir = [:]
            d.set(true, forKey: "tagByDirMigratedV2")
        }
        self.hotkey = HotkeyConfig.load()
        self.layout = LayoutConfig.load()
        applyTheme()
    }

    func tag(for profile: ChromeProfile) -> ProfileTag {
        guard let raw = tagByDir[profile.id], let t = ProfileTag(rawValue: raw) else { return .none }
        return t
    }

    func setTag(_ tag: ProfileTag, for profile: ChromeProfile) {
        if tag == .none {
            tagByDir.removeValue(forKey: profile.id)
        } else {
            tagByDir[profile.id] = tag.rawValue
        }
    }

    func applyTheme() {
        let appearance: NSAppearance?
        switch theme {
        case .system: appearance = nil
        case .light:  appearance = NSAppearance(named: .aqua)
        case .dark:   appearance = NSAppearance(named: .darkAqua)
        }
        NSApp.appearance = appearance
    }

    func applyHotkey() {
        HotkeyManager.shared.apply(hotkey)
    }
}
