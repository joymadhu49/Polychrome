import Foundation
import SwiftUI

enum ProfileTag: String, Codable, CaseIterable, Identifiable {
    case none, red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, gray

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:   return "No tag"
        case .red:    return "Red"
        case .orange: return "Orange"
        case .yellow: return "Yellow"
        case .green:  return "Green"
        case .mint:   return "Mint"
        case .teal:   return "Teal"
        case .blue:   return "Blue"
        case .indigo: return "Indigo"
        case .purple: return "Purple"
        case .pink:   return "Pink"
        case .gray:   return "Gray"
        }
    }

    var color: Color {
        switch self {
        case .none:   return .clear
        case .red:    return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green:  return .green
        case .mint:   return .mint
        case .teal:   return .teal
        case .blue:   return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .pink:   return .pink
        case .gray:   return .gray
        }
    }
}

enum ThemeOverride: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }
}
