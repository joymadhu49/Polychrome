import AppKit
import Combine
import Sparkle

/// Owns Sparkle. Updates come from the appcast attached to the newest GitHub release, and
/// every archive is checked against the EdDSA key in Info.plist before it is installed.
///
/// The update check is the only network request Polychrome makes. It sends nothing about
/// your profiles or browsing, and system profiling is left off.
@MainActor
final class UpdateController: NSObject, ObservableObject {
    static let shared = UpdateController()

    /// False while a check is already running, and always in a build with no feed.
    @Published private(set) var canCheckForUpdates = false
    /// True only for builds that carry a feed — dev builds hide the update UI entirely.
    @Published private(set) var isAvailable = false
    @Published private(set) var lastCheck: Date?
    /// A scheduled check found this version while the user was busy. Shown as a quiet pill
    /// in the menu instead of an alert stealing focus; cleared once the user looks at it.
    @Published private(set) var pendingVersion: String?

    @Published var automaticallyChecks = false {
        didSet {
            guard automaticallyChecks != updater.automaticallyChecksForUpdates else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecks
        }
    }
    @Published var automaticallyDownloads = false {
        didSet {
            guard automaticallyDownloads != updater.automaticallyDownloadsUpdates else { return }
            updater.automaticallyDownloadsUpdates = automaticallyDownloads
        }
    }

    private var controller: SPUStandardUpdaterController!
    private var observations: [NSKeyValueObservation] = []

    private var updater: SPUUpdater { controller.updater }

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false,
                                                  updaterDelegate: nil,
                                                  userDriverDelegate: self)
    }

    /// Called once from launch. A development build without a feed would only log errors,
    /// so the updater is started for the shipped app alone.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        controller.startUpdater()
        isAvailable = true

        automaticallyChecks = updater.automaticallyChecksForUpdates
        automaticallyDownloads = updater.automaticallyDownloadsUpdates
        lastCheck = updater.lastUpdateCheckDate
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheckForUpdates = value }
            },
            updater.observe(\.lastUpdateCheckDate, options: [.new]) { [weak self] updater, _ in
                let value = updater.lastUpdateCheckDate
                Task { @MainActor in self?.lastCheck = value }
            }
        ]
    }

    func checkForUpdates() {
        // A menu bar app is never frontmost on its own, and Sparkle's window would open
        // behind whatever the user was working in.
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

extension UpdateController: SPUStandardUserDriverDelegate {
    /// Polychrome has no Dock icon and is rarely frontmost. Declaring gentle reminders lets
    /// Sparkle show a scheduled update without yanking focus from whatever the user is
    /// typing into, instead of warning that a background app cannot present one well.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Let Sparkle present the alert only when it would get the user's full attention
    /// anyway (just launched, or back from idle). Otherwise the menu shows a pill.
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                          andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool,
                                                               forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        Task { @MainActor in
            if handleShowingUpdate {
                if userInitiated { NSApp.activate(ignoringOtherApps: true) }
            } else {
                self.pendingVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.pendingVersion = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.pendingVersion = nil }
    }
}
