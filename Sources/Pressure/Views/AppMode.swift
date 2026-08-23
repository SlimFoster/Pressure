import SwiftUI

enum AppMode: String, CaseIterable {
    case simple
    case power

    var label: String {
        switch self {
        case .simple: return "Simple"
        case .power: return "Power"
        }
    }
}

enum ColorSchemeOverride: String, CaseIterable {
    case system
    case light
    case dark

    var next: ColorSchemeOverride {
        switch self {
        case .system: return .light
        case .light: return .dark
        case .dark: return .system
        }
    }

    var iconName: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
