import SwiftUI

// MARK: - AdaptiveColor
// Pure ShapeStyle: dark/light values resolved via EnvironmentValues in resolve(in:).
// No UIKit dependency, no View conformance — avoids @Environment/ShapeStyle protocol conflicts.
struct AdaptiveColor: ShapeStyle {
    typealias Resolved = Color

    let dark: Color
    let light: Color

    func resolve(in environment: EnvironmentValues) -> Color {
        environment.colorScheme == .dark ? dark : light
    }

    func opacity(_ opacity: Double) -> AdaptiveColor {
        AdaptiveColor(dark: dark.opacity(opacity), light: light.opacity(opacity))
    }
}

// MARK: - Design Tokens
// Dark: "Pro-Pulse Pick'Em" Stitch system  |  Light: "High-Performance Data System" Stitch system
extension AdaptiveColor {
    static let peBackground   = AdaptiveColor(dark: Color(hex: "131313"), light: Color(hex: "f8f9fa"))
    static let peSurfaceLow   = AdaptiveColor(dark: Color(hex: "1c1b1b"), light: Color(hex: "ffffff"))
    static let peSurface      = AdaptiveColor(dark: Color(hex: "201f1f"), light: Color(hex: "edeeef"))
    static let peSurfaceHigh  = AdaptiveColor(dark: Color(hex: "2a2a2a"), light: Color(hex: "e7e8e9"))
    static let peOnSurface    = AdaptiveColor(dark: Color(hex: "e5e2e1"), light: Color(hex: "191c1d"))
    static let peOnSurfaceVar = AdaptiveColor(dark: Color(hex: "bbc9cf"), light: Color(hex: "3b494c"))
    static let peOutline      = AdaptiveColor(dark: Color(hex: "859399"), light: Color(hex: "6b7a7d"))
    static let peOutlineVar   = AdaptiveColor(dark: Color(hex: "3c494e"), light: Color(hex: "bac9cc"))
    static let pePrimary      = AdaptiveColor(dark: Color(hex: "a4e6ff"), light: Color(hex: "006875"))
    static let pePrimaryFill  = AdaptiveColor(dark: Color(hex: "00d1ff"), light: Color(hex: "00e5ff"))
    static let peOnPrimary    = AdaptiveColor(dark: Color(hex: "003543"), light: Color(hex: "191c1d"))
    static let peSecondary    = AdaptiveColor(dark: Color(hex: "9dd850"), light: Color(hex: "2a5200"))
    static let peOnSecondary  = AdaptiveColor(dark: Color(hex: "1f3700"), light: Color(hex: "ffffff"))
    static let peError        = AdaptiveColor(dark: Color(hex: "ffb4ab"), light: Color(hex: "ba1a1a"))
    static let peTertiary     = AdaptiveColor(dark: Color(hex: "ffaba0"), light: Color(hex: "93000a"))
}

extension Color {
    // Lime fill: constant across modes — chip BG and accent bars (dark text on lime works in both).
    static let peLimeFill = Color(hex: "9dd850")

    init(hex: String) {
        var int: UInt64 = 0
        Scanner(string: hex.trimmingCharacters(in: .alphanumerics.inverted)).scanHexInt64(&int)
        self.init(.sRGB,
                  red:   Double((int >> 16) & 0xFF) / 255,
                  green: Double((int >>  8) & 0xFF) / 255,
                  blue:  Double( int        & 0xFF) / 255)
    }
}

// MARK: - Typography
extension Font {
    static func peDisplay()    -> Font { .system(size: 48, weight: .heavy).width(.condensed) }
    static func peHeadlineLg() -> Font { .system(size: 32, weight: .bold).width(.condensed) }
    static func peHeadlineMd() -> Font { .system(size: 20, weight: .bold).width(.condensed) }
    static func peScore()      -> Font { .system(size: 36, weight: .heavy).width(.condensed) }
    static func peLabelBold()  -> Font { .system(size: 14, weight: .bold).width(.condensed) }
    static func peLabelSm()    -> Font { .system(size: 12, weight: .semibold) }
    static func peBodyMd()     -> Font { .system(size: 16) }
}

// MARK: - View Helpers

extension View {
    /// listRowBackground overload so AdaptiveColor (a ShapeStyle, not View) can be passed directly.
    func listRowBackground(_ color: AdaptiveColor) -> some View {
        self.listRowBackground(Rectangle().fill(color))
    }

    /// Styled text field / secure field container.
    func peFieldStyle() -> some View {
        self
            .foregroundStyle(AdaptiveColor.peOnSurface)
            .padding(14)
            .background(AdaptiveColor.peSurfaceLow)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(AdaptiveColor.peOutlineVar, lineWidth: 1))
    }

    /// Full-screen background that extends under safe areas.
    func peScreenBackground() -> some View {
        self.background(
            Rectangle().fill(AdaptiveColor.peBackground).ignoresSafeArea()
        )
    }
}

// peNavBar() defined per-platform to avoid `some View` opaque-type conflicts across #if branches.
#if os(iOS)
extension View {
    func peNavBar() -> some View {
        self.toolbarBackground(AdaptiveColor.peSurface, for: .navigationBar)
    }
}
#else
extension View {
    func peNavBar() -> some View { self }
}
#endif

// MARK: - Primary Button Style
struct PEPrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.peLabelBold())
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(AdaptiveColor.peOnPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(AdaptiveColor.pePrimaryFill.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Status Chip
struct StatusChip: View {
    enum Style { case live, upcoming, final_, inProgress }

    let label: String
    let style: Style

    var body: some View {
        Text(label)
            .font(.peLabelSm())
            .tracking(0.8)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(fgColor)
            .background(bgColor)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay {
                if style != .live {
                    RoundedRectangle(cornerRadius: 2).stroke(strokeColor, lineWidth: 1)
                }
            }
    }

    // Explicit AnyShapeStyle return type prevents type-checker timeouts on switch expressions.
    private var fgColor: AnyShapeStyle {
        switch style {
        case .live:       AnyShapeStyle(Color(hex: "1f3700"))
        case .upcoming:   AnyShapeStyle(AdaptiveColor.pePrimary)
        case .final_:     AnyShapeStyle(AdaptiveColor.peOnSurfaceVar)
        case .inProgress: AnyShapeStyle(AdaptiveColor.peTertiary)
        }
    }

    private var bgColor: AnyShapeStyle {
        style == .live ? AnyShapeStyle(Color.peLimeFill) : AnyShapeStyle(Color.clear)
    }

    private var strokeColor: AnyShapeStyle {
        switch style {
        case .upcoming:   AnyShapeStyle(AdaptiveColor.pePrimary)
        case .final_:     AnyShapeStyle(AdaptiveColor.peOutline)
        case .inProgress: AnyShapeStyle(AdaptiveColor.peTertiary)
        default:          AnyShapeStyle(Color.clear)
        }
    }
}
