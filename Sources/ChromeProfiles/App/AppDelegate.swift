import Foundation
import AppKit
import SwiftUI
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let loader = ChromeProfileLoader()
    let settings = AppSettings()
    var statusBar: StatusBarController!
    var settingsWindow: NSWindow?
    private var browserObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // Diagnostics only; no-op unless POLYCHROME_AXDUMP=1 is set in the environment.
        WindowFinder.debugDumpAXIfEnabled()

        // Sync loader with the user's enabled-browser selection.
        loader.enabledBrowsers = settings.enabledBrowsers
        browserObserver = settings.$enabledBrowsers.sink { [weak self] new in
            self?.loader.enabledBrowsers = new
        }

        let root = MenuView(
            loader: loader,
            settings: settings,
            openSettings: { [weak self] in self?.openSettings() },
            dismiss: { [weak self] in self?.statusBar.close() }
        )

        statusBar = StatusBarController(rootView: AnyView(root))

        settings.applyHotkey()
        HotkeyManager.shared.onFire = { [weak self] in
            self?.statusBar.toggle()
        }
    }

    func openSettings() {
        statusBar.close()
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(settings: settings)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Polychrome — Settings"
        w.styleMask = [.titled, .closable, .miniaturizable]
        w.isReleasedWhenClosed = false
        w.center()
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
    }
}
