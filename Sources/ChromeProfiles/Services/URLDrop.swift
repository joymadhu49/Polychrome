import Foundation
import AppKit
import UniformTypeIdentifiers

/// Extracts a launchable URL from a drag-and-drop payload — an address-bar drag,
/// a dragged link, or selected text — normalizing bare domains to https://.
enum URLDrop {
    /// Content types profile rows accept as drop targets.
    static let acceptedTypes: [UTType] = [.url, .fileURL, .plainText]

    /// Pasteboard types the status-item drag catcher registers for (AppKit side).
    static let pasteboardTypes: [NSPasteboard.PasteboardType] = [.URL, .fileURL, .string]

    /// Resolve the first usable URL string from the drag's item providers.
    /// The completion is always delivered on the main thread.
    static func load(_ providers: [NSItemProvider], completion: @escaping (String?) -> Void) {
        let finish: (String?) -> Void = { raw in
            let normalized = raw.flatMap(normalize)
            DispatchQueue.main.async { completion(normalized) }
        }
        if let p = providers.first(where: { $0.canLoadObject(ofClass: NSURL.self) }) {
            _ = p.loadObject(ofClass: NSURL.self) { obj, _ in
                finish((obj as? NSURL)?.absoluteString)
            }
            return
        }
        if let p = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) }) {
            _ = p.loadObject(ofClass: NSString.self) { obj, _ in
                finish(obj as? String)
            }
            return
        }
        finish(nil)
    }

    /// Mirror of the search-field quick-launch rules: never a switch-like token,
    /// known schemes pass through, bare domains get https:// prepended.
    static func normalize(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.hasPrefix("-"), !s.contains(" ") else { return nil }
        if let scheme = URL(string: s)?.scheme?.lowercased(),
           ["http", "https", "file", "chrome", "brave"].contains(scheme) {
            return s
        }
        guard s.contains("."), s.count >= 4 else { return nil }
        return "https://" + s
    }
}
