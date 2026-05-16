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
        let themeRaw = d.string(forKey: "theme") ?? ThemeOverride.system.rawValue
        self.theme = ThemeOverride(rawValue: themeRaw) ?? .system
        if let data = d.data(forKey: "tagByDir"),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            self.tagByDir = map
        } else {
            self.tagByDir = [:]
        }
        self.hotkey = HotkeyConfig.load()
        self.layout = LayoutConfig.load()
        applyTheme()
    }

    func tag(for dirName: String) -> ProfileTag {
        guard let raw = tagByDir[dirName], let t = ProfileTag(rawValue: raw) else { return .none }
        return t
    }

    func setTag(_ tag: ProfileTag, for dirName: String) {
        if tag == .none {
            tagByDir.removeValue(forKey: dirName)
        } else {
            tagByDir[dirName] = tag.rawValue
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
