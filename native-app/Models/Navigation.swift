import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case dashboard, environment, fx, logs, settings
    var id: String { rawValue }
    var menuTitle: String { title(true) + " / " + title(false) }
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .environment: return "desktopcomputer"
        case .fx: return "shippingbox"
        case .logs: return "doc.text"
        case .settings: return "gearshape"
        }
    }
    func title(_ zh: Bool) -> String {
        switch self {
        case .dashboard: return zh ? "总览" : "Dashboard"
        case .environment: return zh ? "运行环境" : "Environment"
        case .fx: return zh ? "FX 管理" : "FX Manager"
        case .logs: return zh ? "日志" : "Logs"
        case .settings: return zh ? "设置" : "Settings"
        }
    }
}

enum Appearance: String, CaseIterable {
    case system, light, dark
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    func title(_ zh: Bool) -> String {
        switch self {
        case .system: return zh ? "跟随系统" : "System"
        case .light: return zh ? "浅色" : "Light"
        case .dark: return zh ? "深色" : "Dark"
        }
    }
}
