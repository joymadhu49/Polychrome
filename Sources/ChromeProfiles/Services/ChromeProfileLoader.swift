import Foundation
import AppKit
import Combine

@MainActor
final class ChromeProfileLoader: ObservableObject {
    @Published var profiles: [ChromeProfile] = []
    @Published var lastError: String?

    private var watcher: DispatchSourceFileSystemObject?
    private var watchedFD: CInt = -1

    init() {
        NSLog("[ChromeProfiles] loader init")
        reload()
        startWatching()
    }

    static let chromeRoot: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Application Support/Google/Chrome", isDirectory: true)
    }()

    var localStateURL: URL { Self.chromeRoot.appendingPathComponent("Local State") }

    func reload() {
        NSLog("[ChromeProfiles] reload from \(localStateURL.path)")
        do {
            let data = try Data(contentsOf: localStateURL)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let profileDict = json["profile"] as? [String: Any],
                  let infoCache = profileDict["info_cache"] as? [String: [String: Any]] else {
                self.lastError = "Local State schema unexpected"
                return
            }
            let list: [ChromeProfile] = infoCache.map { (dir, info) in
                let name = info["name"] as? String ?? dir
                let email = info["user_name"] as? String
                let given = info["gaia_given_name"] as? String
                let pic = info["gaia_picture_file_name"] as? String
                var img: NSImage?
                if let pic, !pic.isEmpty {
                    let url = Self.chromeRoot
                        .appendingPathComponent(dir, isDirectory: true)
                        .appendingPathComponent(pic)
                    img = NSImage(contentsOf: url)
                }
                return ChromeProfile(
                    id: dir,
                    dirName: dir,
                    displayName: name,
                    email: email,
                    givenName: given,
                    avatarImage: img
                )
            }
            // sort: Default first, then Profile N numerically, then by name
            self.profiles = list.sorted { a, b in
                func rank(_ p: ChromeProfile) -> (Int, Int, String) {
                    if p.dirName == "Default" { return (0, 0, p.displayName.lowercased()) }
                    if p.dirName.hasPrefix("Profile ") {
                        let n = Int(p.dirName.dropFirst("Profile ".count)) ?? Int.max
                        return (1, n, p.displayName.lowercased())
                    }
                    return (2, 0, p.displayName.lowercased())
                }
                return rank(a) < rank(b)
            }
            self.lastError = nil
            NSLog("[ChromeProfiles] loaded \(self.profiles.count) profiles")
        } catch {
            self.lastError = "Failed to read Local State: \(error.localizedDescription)"
            NSLog("[ChromeProfiles] reload error: \(error)")
        }
    }

    func startWatching() {
        stopWatching()
        let path = localStateURL.path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
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
        watcher = src
        watchedFD = fd
    }

    func stopWatching() {
        watcher?.cancel()
        watcher = nil
        watchedFD = -1
    }
}
