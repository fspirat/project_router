import SwiftUI
import UIKit
import RouterCore

/// Colour tokens from the contract §6 (web/app.css `:root`), light and dark.
/// Every token is a dynamic colour, so `.preferredColorScheme` switches them.
enum Theme {
    // Surfaces
    static let bg = dynamic(light: 0xF6F8FB, dark: 0x090B0F)
    static let surface = dynamic(light: 0xF1F5F9, dark: 0x11151B)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x161B22)
    static let raise = dynamic(light: 0xFFFFFF, dark: 0x1C222B)
    static let hover = dynamic(light: 0xF4F7FA, dark: 0x1A2029)
    static let border = dynamic(light: 0xE2E8F0, dark: 0x252B35)
    static let border2 = dynamic(light: 0xCBD5E1, dark: 0x313946)
    static let line = dynamic(light: 0xEDF1F5, dark: 0x1F252E)

    // Text
    static let text = dynamic(light: 0x0F172A, dark: 0xF1F5F9)
    static let dim = dynamic(light: 0x64748B, dark: 0x94A3B8)
    static let faint = dynamic(light: 0x94A3B8, dark: 0x64748B)

    // Accent (ok)
    static let acc = dynamic(light: 0x059669, dark: 0x34D399)
    static let accText = dynamic(light: 0x047857, dark: 0x34D399)
    static let accPressed = dynamic(light: 0x047857, dark: 0x4ADEA8)
    static let onAcc = dynamic(light: 0xFFFFFF, dark: 0x052E1F)
    static let accSoft = dynamic(light: 0x059669, lightAlpha: 0.08, dark: 0x34D399, darkAlpha: 0.10)
    static let accRing = dynamic(light: 0x059669, lightAlpha: 0.30, dark: 0x34D399, darkAlpha: 0.32)

    // Warn
    static let warn = dynamic(light: 0xB45309, dark: 0xFBBF24)
    static let warnSoft = dynamic(light: 0xD97706, lightAlpha: 0.09, dark: 0xFBBF24, darkAlpha: 0.10)
    static let warnBorder = dynamic(light: 0xD97706, lightAlpha: 0.30, dark: 0xFBBF24, darkAlpha: 0.30)

    // Error
    static let err = dynamic(light: 0xDC2626, dark: 0xF87171)
    static let errFill = dynamic(light: 0xDC2626, dark: 0xDC2626)
    static let errFillPressed = dynamic(light: 0xB91C1C, dark: 0xB91C1C)
    static let errSoft = dynamic(light: 0xDC2626, lightAlpha: 0.06, dark: 0xF87171, darkAlpha: 0.10)
    static let errBorder = dynamic(light: 0xDC2626, lightAlpha: 0.28, dark: 0xF87171, darkAlpha: 0.32)

    // Info
    static let info = dynamic(light: 0x2563EB, dark: 0x60A5FA)
    static let infoSoft = dynamic(light: 0x2563EB, lightAlpha: 0.07, dark: 0x60A5FA, darkAlpha: 0.10)
    static let infoBorder = dynamic(light: 0x2563EB, lightAlpha: 0.25, dark: 0x60A5FA, darkAlpha: 0.30)

    // Chart
    static let chartGrid = dynamic(light: 0x64748B, lightAlpha: 0.12, dark: 0x94A3B8, darkAlpha: 0.09)
    static let area = dynamic(light: 0x059669, lightAlpha: 0.10, dark: 0x34D399, darkAlpha: 0.10)
    static let offline = dynamic(light: 0x64748B, lightAlpha: 0.10, dark: 0x94A3B8, darkAlpha: 0.10)

    // Logo gradient (fixed colours, 145°)
    static let logoTop = Color(red: 52.0 / 255.0, green: 211.0 / 255.0, blue: 153.0 / 255.0)
    static let logoBottom = Color(red: 4.0 / 255.0, green: 120.0 / 255.0, blue: 87.0 / 255.0)

    static func dynamic(light: UInt32, lightAlpha: CGFloat = 1, dark: UInt32, darkAlpha: CGFloat = 1) -> Color {
        let provider = UIColor { trait in
            if trait.userInterfaceStyle == .dark {
                return UIColor(rgb: dark, alpha: darkAlpha)
            }
            return UIColor(rgb: light, alpha: lightAlpha)
        }
        return Color(uiColor: provider)
    }

    // MARK: - Level → colour (contract §6 «Level → colour»)

    /// Dots, bars, lamp.
    static func dot(_ tone: Tone) -> Color {
        switch tone {
        case .ok:
            return acc
        case .warn:
            return warn
        case .err:
            return err
        case .info:
            return info
        case .neutral:
            return faint
        }
    }

    /// Coloured text (ok uses acc-tx).
    static func levelText(_ tone: Tone) -> Color {
        switch tone {
        case .ok:
            return accText
        case .warn:
            return warn
        case .err:
            return err
        case .info:
            return info
        case .neutral:
            return faint
        }
    }

    static func soft(_ tone: Tone) -> Color {
        switch tone {
        case .ok:
            return accSoft
        case .warn:
            return warnSoft
        case .err:
            return errSoft
        case .info:
            return infoSoft
        case .neutral:
            return surface
        }
    }

    static func ring(_ tone: Tone) -> Color {
        switch tone {
        case .ok:
            return accRing
        case .warn:
            return warnBorder
        case .err:
            return errBorder
        case .info:
            return infoBorder
        case .neutral:
            return border
        }
    }

    static func symbol(_ tone: Tone) -> String {
        switch tone {
        case .ok:
            return "checkmark.circle.fill"
        case .warn:
            return "exclamationmark.triangle.fill"
        case .err:
            return "exclamationmark.circle.fill"
        case .info:
            return "info.circle.fill"
        case .neutral:
            return "clock"
        }
    }

    /// The level as a word, for VoiceOver (colour alone is not enough).
    static func levelWord(_ tone: Tone) -> String {
        switch tone {
        case .ok:
            return "в порядке"
        case .warn:
            return "внимание"
        case .err:
            return "проблема"
        case .info:
            return "сведения"
        case .neutral:
            return "проверяется"
        }
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat) {
        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: alpha)
    }
}

/// The theme setting («Как в системе / Светлая / Тёмная»), stored in `@AppStorage("theme")`.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        return rawValue
    }

    var title: String {
        switch self {
        case .system:
            return "Как в системе"
        case .light:
            return "Светлая"
        case .dark:
            return "Тёмная"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}
