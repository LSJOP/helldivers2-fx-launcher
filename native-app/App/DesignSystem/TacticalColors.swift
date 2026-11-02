import SwiftUI

// Terminal UI 2.1 colors plus explicit GUI/light-mode additions. See design spec.
struct TacticalColors {
    let scheme: ColorScheme
    private func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        let hex = scheme == .dark ? dark : light
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    var background: Color { adaptive(0x101114, 0xEEEFE9) }
    var secondary: Color { adaptive(0x181A1E, 0xE3E5DD) }
    var panel: Color { adaptive(0x202328, 0xFAFBF6) }
    var yellow: Color { adaptive(0xFFD600, 0xFFD600) }
    var accent: Color { adaptive(0xFFD600, 0x695600) }
    var ink: Color { adaptive(0x101114, 0x101114) }
    var text: Color { adaptive(0xDFE2E8, 0x202328) }
    var muted: Color { adaptive(0xA5A8AD, 0x565C63) }
    var line: Color { adaptive(0x41454D, 0xBCC0B7) }
    var success: Color { adaptive(0x55D68A, 0x237247) }
    var warning: Color { adaptive(0xFF6B4A, 0xA43B22) }
    var error: Color { adaptive(0xFF5757, 0xAF2929) }
}
