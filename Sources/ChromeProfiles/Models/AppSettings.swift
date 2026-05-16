import Foundation
import Combine

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
        self.launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        self.showEmails = (UserDefaults.standard.object(forKey: "showEmails") as? Bool) ?? true
        self.focusExisting = (UserDefaults.standard.object(forKey: "focusExisting") as? Bool) ?? true
        self.hotkey = HotkeyConfig.load()
        self.layout = LayoutConfig.load()
    }

    func applyHotkey() {
        HotkeyManager.shared.apply(hotkey)
    }
}
