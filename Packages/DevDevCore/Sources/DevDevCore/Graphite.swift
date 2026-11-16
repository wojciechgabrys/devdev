import AppKit
import SwiftUI

/// The Graphite look shared by the App and the Helper: a dark pro-tool palette with a matching light
/// one. Every colour follows the system appearance. Views take colours from here, never inline.
public enum Graphite {
    // MARK: Surfaces

    /// The output area and the window's main surface.
    public static let canvas = color(dark: 0x1B1B1F, light: 0xFBFBFC)
    /// Title strip, project tree, tab bar, status bar.
    public static let chrome = color(dark: 0x202025, light: 0xF3F3F6)
    /// Chips, segmented controls, unselected fields.
    public static let raised = color(dark: 0x26262C, light: 0xECECF0)
    public static let hover = color(dark: 0x2A2A31, light: 0xE6E6EB)
    public static let line = color(dark: 0x2C2C33, light: 0xE2E2E8)

    // MARK: Text

    public static let text = color(dark: 0xD7D7DE, light: 0x24242A)
    public static let strong = color(dark: 0xECECF1, light: 0x0F0F12)
    public static let secondary = color(dark: 0x8D8D99, light: 0x6A6A76)
    public static let tertiary = color(dark: 0x62626E, light: 0x9A9AA6)

    // MARK: Accent and statuses

    /// The accent colour picked in System Settings > Appearance. It changes live when the user picks another.
    public static let accent = Color(nsColor: .controlAccentColor)
    /// A faint wash of the system accent, for the selected row.
    public static let selection = Color(
        nsColor: NSColor(name: nil) { appearance in
            let alpha: CGFloat = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? 0.28 : 0.18
            return NSColor.controlAccentColor.withAlphaComponent(alpha)
        })
    public static let green = color(dark: 0x3DDC84, light: 0x1F9D57)
    public static let red = color(dark: 0xFF6B6B, light: 0xD93B3B)
    public static let blue = color(dark: 0x6EA8FF, light: 0x2F6FDE)
    public static let amber = color(dark: 0xF5C451, light: 0xB7791F)

    /// A steady colour per Project for its folder icon, picked from its id.
    public static func projectTint(_ id: UUID) -> Color {
        let tints: [Color] = [
            color(dark: 0xF07B3F, light: 0xE8590C), color(dark: 0x9D8BFF, light: 0x7C5CFF),
            color(dark: 0x2DD4BF, light: 0x0D9488), color(dark: 0x38BDF8, light: 0x0284C7),
            color(dark: 0xF472B6, light: 0xDB2777), color(dark: 0xFACC15, light: 0xCA8A04),
            color(dark: 0x4ADE80, light: 0x16A34A), color(dark: 0xA3A3B2, light: 0x6B7280),
        ]
        return tints[Int(id.uuid.0) % tints.count]
    }

    // MARK: Type

    public static let mono = Font.system(size: 11, design: .monospaced)
    public static let monoSmall = Font.system(size: 10.5, design: .monospaced)
    public static let sectionLabel = Font.system(size: 10.5, weight: .bold)

    // MARK: Terminal

    /// Colours for the output view, for one appearance. SwiftTerm needs concrete colours.
    public struct TerminalColors {
        public var background: NSColor
        public var foreground: NSColor
        public var selection: NSColor
        /// The 16 ANSI colours: normal 0–7, then bright 8–15.
        public var ansi: [NSColor]
    }

    public static func terminalColors(dark: Bool) -> TerminalColors {
        let hex: [UInt32] =
            dark
            ? [
                0x2A2A31, 0xFF6B6B, 0x3DDC84, 0xF5C451, 0x8AB4FF, 0xC4A7FF, 0x6FD3D8, 0xD7D7DE,
                0x5F5F6B, 0xFF8A8A, 0x6BE9A3, 0xFFD97A, 0xA8C7FF, 0xD6C2FF, 0x92E3E7, 0xFFFFFF,
            ]
            : [
                0x24242A, 0xD93B3B, 0x1F9D57, 0xB7791F, 0x2F6FDE, 0x7E57C2, 0x1B8A99, 0xDADAE0,
                0x8A8A96, 0xE5534B, 0x2DB36A, 0xC98A1E, 0x4A86F0, 0x9575CD, 0x23A3B5, 0xFFFFFF,
            ]
        return TerminalColors(
            background: nsColor(dark ? 0x1B1B1F : 0xFBFBFC),
            foreground: nsColor(dark ? 0xD7D7DE : 0x24242A),
            selection: NSColor.controlAccentColor.withAlphaComponent(dark ? 0.35 : 0.22),
            ansi: hex.map { nsColor($0) })
    }

    // MARK: Helpers

    static func nsColor(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    static func color(dark: UInt32, light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? nsColor(dark, alpha: darkAlpha) : nsColor(light, alpha: lightAlpha)
            })
    }
}

extension CommandStatus {
    public var graphiteColor: Color {
        switch self {
        case .stopped: Graphite.tertiary
        case .running: Graphite.green
        case .finished: Graphite.blue
        case .crashed: Graphite.red
        }
    }
}

extension ProjectStatus {
    public var graphiteColor: Color {
        switch self {
        case .stopped: Graphite.tertiary
        case .running: Graphite.green
        case .partlyRunning: Graphite.amber
        case .crashed: Graphite.red
        }
    }
}

/// The small mark beside a Command: a glowing dot while Running, a ring when Stopped,
/// a red diamond when Crashed, a blue dot when Finished.
public struct StatusGlyph: View {
    public enum Kind: Equatable {
        case command(CommandStatus)
        case project(ProjectStatus)
    }

    let kind: Kind

    public init(_ status: CommandStatus) { kind = .command(status) }
    public init(_ status: ProjectStatus) { kind = .project(status) }

    public var body: some View {
        ZStack {
            switch kind {
            case .command(.running), .project(.running):
                Circle().fill(Graphite.green).frame(width: 7, height: 7)
                    .shadow(color: Graphite.green.opacity(0.6), radius: 3)
            case .command(.stopped), .project(.stopped):
                Circle().strokeBorder(Graphite.tertiary, lineWidth: 1.5).frame(width: 7, height: 7)
            case .command(.crashed), .project(.crashed):
                RoundedRectangle(cornerRadius: 1.5).fill(Graphite.red).frame(width: 6.5, height: 6.5)
                    .rotationEffect(.degrees(45))
            case .command(.finished):
                Circle().fill(Graphite.blue).frame(width: 7, height: 7)
            case .project(.partlyRunning):
                Circle().fill(Graphite.tertiary).frame(width: 7, height: 7)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Graphite.amber).frame(width: 3.5, height: 7)
                    }
                    .clipShape(Circle())
            }
        }
        .frame(width: 10, height: 10)
        .accessibilityHidden(true)
    }
}

/// A small square icon button that lights up on hover, used across the Graphite views.
public struct GraphiteIconButton: View {
    let symbol: String
    let help: String
    let size: CGFloat
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    public init(_ symbol: String, help: String, size: CGFloat = 22, action: @escaping () -> Void) {
        self.symbol = symbol
        self.help = help
        self.size = size
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .frame(width: size, height: size)
                .foregroundStyle(isHovering && isEnabled ? Graphite.strong : Graphite.secondary)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(isHovering && isEnabled ? Graphite.hover : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.3)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
