import AppKit

/// Plain AppKit entry point. Polychrome used to declare a SwiftUI `App` with a
/// placeholder `Settings { EmptyView() }` scene just to satisfy the lifecycle, and
/// SwiftUI would open that empty scene as a blank "Polychrome Settings" window at
/// launch. A menu bar app has no scenes to manage, so there is nothing to open now;
/// the real Settings window is built by `AppDelegate.openSettings`.
@main
enum PolychromeMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()   // held for the process lifetime; run() never returns
        app.delegate = delegate
        app.run()
    }
}
