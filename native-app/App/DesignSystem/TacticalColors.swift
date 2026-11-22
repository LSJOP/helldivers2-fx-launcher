import SwiftUI

// Terminal UI 2.1 colors plus explicit GUI/light-mode additions. See design spec.
struct TacticalColors {
    let scheme: ColorScheme
    private func adaptive(_ dark: UInt32, _ light: UInt32) -> Color {
        let hex = scheme == .dark ? dark : light
        return Color(red: Double((hex >> 16) & 255) / 255,
                     green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    var background: Color { adaptive(0x111316, 0xE8E9E4) }
    var secondary: Color { adaptive(0x181C21, 0xDADDD5) }
    var panel: Color { adaptive(0x22272E, 0xF6F7F2) }
    var yellow: Color { adaptive(0xFFD500, 0xFFD500) }
    var accent: Color { adaptive(0xFFD500, 0x695600) }
    var ink: Color { adaptive(0x101114, 0x101114) }
    var text: Color { adaptive(0xE8EBEF, 0x20252A) }
    var muted: Color { adaptive(0xA0A7B0, 0x596168) }
    var line: Color { adaptive(0x414750, 0xB9BEB5) }
    var success: Color { adaptive(0x2EC27E, 0x237247) }
    var warning: Color { adaptive(0xFFD500, 0x795C00) }
    var error: Color { adaptive(0xFF5C5C, 0xAF2929) }
    var elevated: Color { adaptive(0x2B3138, 0xFFFFFF) }
    var hover: Color { adaptive(0x2F353D, 0xEBEEE5) }
    var pressed: Color { adaptive(0x262B31, 0xDFE3D6) }
    var selected: Color { adaptive(0x292B2A, 0xF8F5E9) }
    var selectedHover: Color { adaptive(0x32342F, 0xFAF2D9) }
    var disabled: Color { adaptive(0x3A3F46, 0xE3E5DE) }
    var unknown: Color { adaptive(0x8B919A, 0x686F76) }
    var primaryHover: Color { adaptive(0xFFE053, 0xF8E28B) }
    var primaryPressed: Color { adaptive(0xDDB800, 0xE2C648) }
}
