import Foundation
import AppKit
import SwiftUI

extension Notification.Name {
    static let polychromeMenuWillShow = Notification.Name("Polychrome.menuWillShow")
}

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var globalMonitor: Any?
    private var deactivateObserver: Any?
    private var pinned = false

    init(rootView: AnyView) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.appearance = nil
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 280, height: 440)

        if let button = statusItem.button {
            let img = NSImage(systemSymbolName: "rectangle.3.group.bubble.left.fill",
                              accessibilityDescription: "Polychrome")
            img?.isTemplate = true
            button.image = img
            button.target = self
            button.action = #selector(buttonClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Dismiss on click-outside (popover.behavior = .transient handles this for most apps, redundancy safe).
        // Skipped while pinned — that's the whole point of the pin.
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.popover.isShown && !self.pinned { self.popover.performClose(nil) }
        }

        // When another app activates (e.g. Chrome right after launching a profile),
        // its windows would stack above the pinned menu — re-assert ours on top.
        deactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.pinned, self.popover.isShown { self.applyPinnedWindowLevel() }
            }
        }
    }

    /// Pinned: the popover survives clicks outside and stays above other apps' windows.
    func setPinned(_ on: Bool) {
        pinned = on
        popover.behavior = on ? .applicationDefined : .transient
        applyPinnedWindowLevel()
    }

    private func applyPinnedWindowLevel() {
        guard pinned, let window = popover.contentViewController?.view.window else { return }
        // Only ever raise — AppKit may already host the popover above .floating.
        if window.level.rawValue < NSWindow.Level.floating.rawValue {
            window.level = .floating
        }
        // Behave like a real floating panel: follow Space switches, show over
        // fullscreen windows, and never hide just because the app lost focus.
        window.collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
        window.hidesOnDeactivate = false
        window.orderFrontRegardless()
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
        if let o = deactivateObserver { NotificationCenter.default.removeObserver(o) }
    }

    @objc private func buttonClick(_ sender: Any?) {
        toggle()
    }

    func toggle() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            show()
        }
    }

    func show() {
        guard let button = statusItem.button else { return }
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        applyPinnedWindowLevel()
        NotificationCenter.default.post(name: .polychromeMenuWillShow, object: nil)
    }

    func close() {
        popover.performClose(nil)
    }

    func updateRootView(_ rootView: AnyView) {
        (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = rootView
    }
}
