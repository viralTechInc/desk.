import SwiftUI

/// The restrained color category system for time blocks.
enum BlockCategory: String, CaseIterable, Codable, Sendable, Identifiable {
    case work
    case personal
    case admin
    case relationships
    case fitness
    case ownProjects

    var id: String { rawValue }

    var label: String {
        switch self {
        case .work: "Work"
        case .personal: "Personal"
        case .admin: "Admin"
        case .relationships: "Relationships"
        case .fitness: "Fitness"
        case .ownProjects: "Own projects"
        }
    }

    /// Base hue (filled block background).
    var color: Color {
        switch self {
        case .work: Color(hex: 0x527FC9)
        case .personal: Color(hex: 0x78A58A)
        case .admin: Color(hex: 0xC69C67)
        case .relationships: Color(hex: 0xCF86B0)
        case .fitness: Color(hex: 0xD77F80)
        case .ownProjects: Color(hex: 0x6AB18E)
        }
    }

    /// Deeper ink used for block text so it stays legible on the tinted fill.
    var inkColor: Color {
        switch self {
        case .work: Color(hex: 0x1E3D6E)
        case .personal: Color(hex: 0x264A35)
        case .admin: Color(hex: 0x5C4218)
        case .relationships: Color(hex: 0x60274B)
        case .fitness: Color(hex: 0x6A2426)
        case .ownProjects: Color(hex: 0x1F4D37)
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}
