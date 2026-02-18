import SwiftUI

// MARK: - Colors (from Stitch: #590DF2 accent, dark theme)

struct AppColors {
    // Primary accent — purple/indigo from Stitch
    static let accent = Color(hex: "590DF2")
    static let accentLight = Color(hex: "7B3FF2")
    static let accentDark = Color(hex: "4108B8")

    // Gradient
    static let accentGradient = LinearGradient(
        colors: [Color(hex: "590DF2"), Color(hex: "8B5CF6")],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let waveformGradient = LinearGradient(
        colors: [Color(hex: "590DF2"), Color(hex: "A78BFA"), Color(hex: "590DF2")],
        startPoint: .leading,
        endPoint: .trailing
    )

    // Backgrounds
    static let background = Color(hex: "1C1C1E")
    static let backgroundSecondary = Color(hex: "2C2C2E")
    static let surface = Color.white.opacity(0.06)
    static let surfaceHover = Color.white.opacity(0.10)
    static let surfaceBorder = Color.white.opacity(0.08)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.4)

    // Semantic
    static let success = Color(hex: "34C759")
    static let error = Color(hex: "FF3B30")
    static let warning = Color(hex: "FF9500")
}

// MARK: - Typography (SF Pro — system default, matches Stitch Inter mapping)

struct AppTypography {
    static let largeTitle = Font.system(size: 26, weight: .bold, design: .default)
    static let title = Font.system(size: 20, weight: .semibold, design: .default)
    static let title2 = Font.system(size: 17, weight: .semibold, design: .default)
    static let headline = Font.system(size: 15, weight: .semibold, design: .default)
    static let body = Font.system(size: 13, weight: .regular, design: .default)
    static let bodyMedium = Font.system(size: 13, weight: .medium, design: .default)
    static let caption = Font.system(size: 11, weight: .regular, design: .default)
    static let captionMedium = Font.system(size: 11, weight: .medium, design: .default)
    static let timer = Font.system(size: 24, weight: .light, design: .monospaced)
    static let shortcutKey = Font.system(size: 32, weight: .medium, design: .rounded)
}

// MARK: - Spacing (8pt grid from Stitch)

struct AppSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let xxxl: CGFloat = 48
}

// MARK: - Corner Radius (from Stitch: ROUND_EIGHT = 8pt)

struct AppRadius {
    static let sm: CGFloat = 4
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let full: CGFloat = 999
}

// MARK: - Shadows & Effects

struct AppEffects {
    static let glowRadius: CGFloat = 20
    static let glowOpacity: Double = 0.3
    static let overlayBlurRadius: CGFloat = 30
}

// MARK: - Animation

struct AppAnimation {
    static let standard = Animation.easeInOut(duration: 0.25)
    static let slow = Animation.easeInOut(duration: 0.5)
    static let spring = Animation.spring(response: 0.4, dampingFraction: 0.75)
    static let waveform = Animation.linear(duration: 0.05)
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
