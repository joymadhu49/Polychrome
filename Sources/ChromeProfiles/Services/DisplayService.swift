import Foundation
import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool

    // CGRect is Equatable but not Hashable, so the compiler can't synthesize
    // Hashable — hash the rects' scalar components instead.
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(isMain)
        for r in [frame, visibleFrame] {
            hasher.combine(r.origin.x)
            hasher.combine(r.origin.y)
            hasher.combine(r.size.width)
            hasher.combine(r.size.height)
        }
    }
}

enum DisplayService {
    /// `isMain` marks the primary display — the one carrying the menu bar, which AppKit always
    /// lists first. (`NSScreen.main` is whichever screen holds the key window, so "Main display"
    /// used to depend on where the menu happened to be.)
    static func screens() -> [DisplayInfo] {
        let primary = NSScreen.screens.first
        return NSScreen.screens.enumerated().compactMap { idx, screen in
            guard let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            let id = num.uint32Value
            let name = screen.localizedName.isEmpty ? "Display \(idx + 1)" : screen.localizedName
            return DisplayInfo(
                id: id,
                name: name,
                frame: screen.frame,
                visibleFrame: screen.visibleFrame,
                isMain: screen == primary
            )
        }
    }

    static func screen(for id: UInt32?) -> DisplayInfo {
        let all = screens()
        if let id, let match = all.first(where: { $0.id == id }) { return match }
        return all.first(where: { $0.isMain }) ?? all.first ?? DisplayInfo(
            id: 0, name: "Main", frame: .zero, visibleFrame: .zero, isMain: true
        )
    }
}
