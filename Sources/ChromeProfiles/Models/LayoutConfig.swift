import Foundation
import AppKit

enum TileLayout: String, Codable, CaseIterable, Identifiable {
    case smart, row, column, grid, splitH, splitV

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .smart:   return "Smart (auto-fit)"
        case .row:     return "Row — 1 × N"
        case .column:  return "Column — N × 1"
        case .grid:    return "Grid — square-ish"
        case .splitH:  return "Split — left pane + stack"
        case .splitV:  return "Split — top pane + stack"
        }
    }

    var icon: String {
        switch self {
        case .smart:  return "rectangle.3.group"
        case .row:    return "rectangle.split.3x1"
        case .column: return "rectangle.split.1x2"
        case .grid:   return "square.grid.2x2"
        case .splitH: return "rectangle.lefthalf.filled"
        case .splitV: return "rectangle.tophalf.filled"
        }
    }
}

struct LayoutConfig: Codable, Equatable {
    var layout: TileLayout = .smart
    var displayID: UInt32? = nil           // nil = main; matches NSScreen.deviceDescription[\.screenNumber]
    var paddingPx: CGFloat = 8
    var avoidMenubar: Bool = true
    var splitPercent: Double = 0.5         // for splitH/splitV when 2 windows

    static let storageKey = "LayoutConfig.v1"

    static func load() -> LayoutConfig {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let cfg = try? JSONDecoder().decode(LayoutConfig.self, from: data) else {
            return LayoutConfig()
        }
        return cfg
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
