import Foundation
import AppKit

struct DisplayInfo: Identifiable, Hashable {
    let id: UInt32
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let isMain: Bool
}

enum DisplayService {
    static func screens() -> [DisplayInfo] {
        NSScreen.screens.enumerated().compactMap { idx, screen in
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
                isMain: screen == NSScreen.main
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
