import Foundation
import AppKit
import SwiftUI
import Combine

/// Which Settings pane is showing. Owned by the app delegate so the menu can open
/// Settings straight to the pane that fixes a problem (e.g. an unavailable hotkey).
@MainActor
final class SettingsRouter: ObservableObject {
    @Published var pane: SettingsPane = .general
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let loader = ChromeProfileLoader()
    let settings = AppSettings()
    let router = SettingsRouter()
    var statusBar: StatusBarController!
    var settingsWindow: NSWindow?
    private var browserObserver: AnyCancellable?
    private var pinObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.makeMainMenu()

        // Diagnostics only; no-op unless POLYCHROME_AXDUMP=1 is set in the environment.
        WindowFinder.debugDumpAXIfEnabled()

        // Sync loader with the user's enabled-browser selection.
        loader.enabledBrowsers = settings.enabledBrowsers
        browserObserver = settings.$enabledBrowsers.sink { [weak self] new in
            self?.loader.enabledBrowsers = new
        }

        UpdateController.shared.start()

        let root = MenuView(
            loader: loader,
            settings: settings,
            updates: UpdateController.shared,
            openSettings: { [weak self] pane in self?.openSettings(pane) },
            dismiss: { [weak self] in self?.statusBar.close() }
        )

        statusBar = StatusBarController(rootView: AnyView(root))
        pinObserver = settings.$pinned.sink { [weak self] in self?.statusBar.setPinned($0) }

        HotkeyManager.shared.onFire = { [weak self] in
            self?.statusBar.toggle()
        }
        settings.applyHotkey()
    }

    /// Never shown (the app is an accessory with no menu bar of its own), but AppKit
    /// routes ⌘X/⌘C/⌘V/⌘A/⌘Z through the main menu's key equivalents. Without it, the
    /// search field and Settings text would silently ignore copy and paste.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Polychrome", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowItem.submenu = window
        main.addItem(windowItem)
        return main
    }

    func openSettings(_ pane: SettingsPane? = nil) {
        statusBar.close()
        if let pane { router.pane = pane }
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(settings: settings, updates: UpdateController.shared, router: router)
        let host = NSHostingController(rootView: view)
        let w = NSWindow(contentViewController: host)
        w.title = "Polychrome Settings"
        // Full-size content lets the sidebar run under the title bar, the way
        // System Settings and every modern Mac settings window look.
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.toolbarStyle = .unified
        w.isReleasedWhenClosed = false
        w.setFrameAutosaveName("PolychromeSettings")
        if !w.setFrameUsingName("PolychromeSettings") { w.center() }
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = w
    }
}
