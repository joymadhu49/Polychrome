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
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            if self.popover.isShown { self.popover.performClose(nil) }
        }
    }

    deinit {
        if let m = globalMonitor { NSEvent.removeMonitor(m) }
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
        NotificationCenter.default.post(name: .polychromeMenuWillShow, object: nil)
    }

    func close() {
        popover.performClose(nil)
    }

    func updateRootView(_ rootView: AnyView) {
        (popover.contentViewController as? NSHostingController<AnyView>)?.rootView = rootView
    }
}
