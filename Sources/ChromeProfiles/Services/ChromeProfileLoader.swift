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

    init() {
        NSLog("[ChromeProfiles] loader init")
        reload()
        startWatching()
    }

    deinit {
        for w in watchers { w.cancel() }
    }

    func reload() {
        var all: [ChromeProfile] = []
        var errors: [String] = []
        for browser in enabledBrowsers where browser.isInstalled {
            do {
                let part = try loadProfiles(for: browser)
                all.append(contentsOf: part)
            } catch {
                errors.append("\(browser.displayName): \(error.localizedDescription)")
            }
        }
        self.profiles = sorted(all)
        self.lastError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        NSLog("[ChromeProfiles] loaded \(self.profiles.count) profiles across \(enabledBrowsers.count) browsers")
    }

    private func loadProfiles(for browser: Browser) throws -> [ChromeProfile] {
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

    private func sorted(_ list: [ChromeProfile]) -> [ChromeProfile] {
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
                self?.reload()
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
