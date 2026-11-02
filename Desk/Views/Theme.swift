import SwiftUI
import AppKit

/// Desk's visual vocabulary: a warm paper canvas, a white writing surface, quiet ink.
enum Theme {
    // MARK: Colors (light / dark)
    static let canvas = dynamic(light: 0xFAF8F4, dark: 0x1B1A18)
    static let surface = dynamic(light: 0xFFFFFF, dark: 0x232220)
    static let surfaceRaised = dynamic(light: 0xFDFCFA, dark: 0x2A2927)
    static let ink = dynamic(light: 0x242424, dark: 0xECE8E1)
    static let inkMuted = dynamic(light: 0x737373, dark: 0x8F8B84)
    static let inkFaint = dynamic(light: 0xB5B0A8, dark: 0x5E5B55)
    static let hairline = dynamic(light: 0xE8E4DD, dark: 0x34322E)
    static let hairlineStrong = dynamic(light: 0xD9D4CB, dark: 0x45423D)
    static let ruledLine = dynamic(light: 0xEEEBE5, dark: 0x2E2D2A)
    static let accent = dynamic(light: 0x527FC9, dark: 0x7FA3E0)
    static let nowLine = dynamic(light: 0xC8553D, dark: 0xE0735C)
    static let danger = dynamic(light: 0xB4473A, dark: 0xE07A6D)
    static let selection = dynamic(light: 0xEFF3FA, dark: 0x2C3240)

    // MARK: Type
    static let dateHeading = Font.system(size: 31, weight: .regular, design: .serif)
    static let weekHeading = Font.system(size: 26, weight: .regular, design: .serif)
    static let body = Font.system(size: 15.5)
    static let bodyMedium = Font.system(size: 15.5, weight: .medium)
    static let priority = Font.system(size: 16)
    static let eventLabel = Font.system(size: 13, weight: .medium)
    static let eventTime = Font.system(size: 11.5)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let gutter = Font.system(size: 11, weight: .regular, design: .default).monospacedDigit()
    static let toolbar = Font.system(size: 13, weight: .medium)
    static let caption = Font.system(size: 12)
    static let wordmark = Font.system(size: 20, weight: .medium, design: .serif).italic()

    // MARK: Spacing
    static let margin: CGFloat = 32
    static let padding: CGFloat = 24
    static let radius: CGFloat = 6
    static let gutterWidth: CGFloat = 52
    /// Above the page heading. The hidden title bar already keeps a 28pt safe area for the
    /// window controls, so this only adds breathing room.
    static let headerTop: CGFloat = 12
    static let footerHeight: CGFloat = 40
    /// Gap between a page's card and the footer.
    static let pageBottom: CGFloat = 8

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Uppercase, letter-spaced section label (TOP PRIORITIES, BRAIN DUMP, SCHEDULE).
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.sectionLabel)
            .tracking(1.3)
            .foregroundStyle(Theme.inkMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Quiet text button used in the toolbar.
struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.toolbar)
            .foregroundStyle(prominent ? Theme.ink : Theme.inkMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering || configuration.isPressed ? Theme.hairline.opacity(configuration.isPressed ? 1 : 0.7) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(prominent ? Theme.hairlineStrong : .clear, lineWidth: 1)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Icon-only toolbar button.
struct IconButtonStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.inkMuted)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(hovering || configuration.isPressed ? Theme.hairline.opacity(configuration.isPressed ? 1 : 0.7) : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// Day / Week switcher drawn as a restrained segmented control.
struct ViewModeSwitcher: View {
    @Binding var mode: ViewMode
    var body: some View {
        HStack(spacing: 2) {
            ForEach(ViewMode.allCases) { m in
                Button(m.label) { mode = m }
                    .buttonStyle(.plain)
                    .font(Theme.toolbar)
                    .foregroundStyle(mode == m ? Theme.ink : Theme.inkMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(mode == m ? Theme.surface : .clear)
                            .shadow(color: mode == m ? .black.opacity(0.06) : .clear, radius: 1, y: 1)
                    )
                    .accessibilityAddTraits(mode == m ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.hairline.opacity(0.8)))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("View")
    }
}

/// Hairline rule, horizontal or vertical.
struct Hairline: View {
    var vertical = false
    var color: Color = Theme.hairline
    var body: some View {
        Rectangle().fill(color)
            .frame(width: vertical ? 1 : nil, height: vertical ? nil : 1)
    }
}
