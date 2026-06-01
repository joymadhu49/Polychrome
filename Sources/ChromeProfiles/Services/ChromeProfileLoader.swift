import Foundation
import AppKit
import Combine

@MainActor
final class ChromeProfileLoader: ObservableObject {
    @Published var profiles: [ChromeProfile] = []
    @Published var lastError: String?

    /// Browsers the user wants to load. Re-assign to switch sources.
    var enabledBrowsers: Set<Browser> = [.chrome, .brave] {
        didSet {
            guard oldValue != enabledBrowsers else { return }
            reload()
            startWatching()
        }
    }

    private var watchers: [DispatchSourceFileSystemObject] = []
    private var reloadTask: Task<Void, Never>?
    private var debounceTask: Task<Void, Never>?

    init() {
        NSLog("[ChromeProfiles] loader init")
        reload()
        startWatching()
    }

    deinit {
        for w in watchers { w.cancel() }
        reloadTask?.cancel()
        debounceTask?.cancel()
    }

    /// Reload profiles. The disk read, JSON parse, and avatar image decoding run off the main
    /// thread; only the published results are assigned back on the main actor, so a watcher
    /// firing during heavy Chrome activity never hitches the UI.
    func reload() {
        let browsers = enabledBrowsers
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                ChromeProfileLoader.loadAll(browsers: browsers)
            }.value
            if Task.isCancelled { return }
            self?.profiles = result.profiles
            self?.lastError = result.errors.isEmpty ? nil : result.errors.joined(separator: "\n")
            NSLog("[ChromeProfiles] loaded \(result.profiles.count) profiles across \(browsers.count) browsers")
        }
    }

    /// Coalesce bursts of file-system events (Chrome rewrites Local State repeatedly) into a single
    /// reload, and re-establish the watchers afterwards: Chrome replaces Local State atomically
    /// (write-temp + rename), which leaves our file descriptor pointing at the old, unlinked inode
    /// so events would otherwise stop arriving.
    private func scheduleReloadAndRewatch() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            self.reload()
            self.startWatching()
        }
    }

    private nonisolated static func loadAll(browsers: Set<Browser>) -> (profiles: [ChromeProfile], errors: [String]) {
        var all: [ChromeProfile] = []
        var errors: [String] = []
        for browser in browsers where browser.isInstalled {
            do {
                let part = try loadProfiles(for: browser)
                all.append(contentsOf: part)
            } catch {
                errors.append("\(browser.displayName): \(error.localizedDescription)")
            }
        }
        return (sorted(all), errors)
    }

    private nonisolated static func loadProfiles(for browser: Browser) throws -> [ChromeProfile] {
        let url = browser.localStateURL
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profileDict = json["profile"] as? [String: Any],
              let infoCache = profileDict["info_cache"] as? [String: [String: Any]] else {
            throw NSError(domain: "Polychrome", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local State schema unexpected"])
        }
        return infoCache.map { (dir, info) in
            let name = info["name"] as? String ?? dir
            let email = info["user_name"] as? String
            let given = info["gaia_given_name"] as? String
            let pic = info["gaia_picture_file_name"] as? String
            var img: NSImage?
            if let pic, !pic.isEmpty {
                let picURL = browser.dataDir
                    .appendingPathComponent(dir, isDirectory: true)
                    .appendingPathComponent(pic)
                img = NSImage(contentsOf: picURL)
            }
            return ChromeProfile(
                browser: browser,
                dirName: dir,
                displayName: name,
                email: email,
                givenName: given,
                avatarImage: img
            )
        }
    }

    private nonisolated static func sorted(_ list: [ChromeProfile]) -> [ChromeProfile] {
        list.sorted { a, b in
            func rank(_ p: ChromeProfile) -> (Int, Int, Int, String) {
                let browserRank = (p.browser == .chrome) ? 0 : 1
                if p.dirName == "Default" { return (browserRank, 0, 0, p.displayName.lowercased()) }
                if p.dirName.hasPrefix("Profile ") {
                    let n = Int(p.dirName.dropFirst("Profile ".count)) ?? Int.max
                    return (browserRank, 1, n, p.displayName.lowercased())
                }
                return (browserRank, 2, 0, p.displayName.lowercased())
            }
            return rank(a) < rank(b)
        }
    }

    func startWatching() {
        stopWatching()
        for browser in enabledBrowsers where browser.isInstalled {
            let path = browser.localStateURL.path
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let src = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: [.write, .delete, .rename, .attrib],
                queue: .main
            )
            src.setEventHandler { [weak self] in
                self?.scheduleReloadAndRewatch()
            }
            src.setCancelHandler { close(fd) }
            src.resume()
            watchers.append(src)
        }
    }

    func stopWatching() {
        for w in watchers { w.cancel() }
        watchers.removeAll()
    }
}
