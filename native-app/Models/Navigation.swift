import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case dashboard, environment, fx, performance, logs, settings
    var id: String { rawValue }
    var menuTitle: String { title("en") }
    var symbol: String {
        switch self {
        case .dashboard: return "square.grid.2x2"
        case .environment: return "desktopcomputer"
        case .fx: return "shippingbox"
        case .performance: return "speedometer"
        case .logs: return "doc.text"
        case .settings: return "gearshape"
        }
    }
    func title(_ zh: Bool) -> String { title(zh ? "zh-CN" : "en") }
    func title(_ language: String) -> String {
        switch self {
        case .dashboard: return NativeStrings.text("ui.092", language: language)
        case .environment: return NativeStrings.text("ui.107", language: language)
        case .fx: return NativeStrings.text("ui.117", language: language)
        case .performance: return NativeStrings.text("ui.134", language: language)
        case .logs: return NativeStrings.text("ui.187", language: language)
        case .settings: return NativeStrings.text("ui.308", language: language)
        }
    }
}

enum Appearance: String, CaseIterable {
    case system, light, dark
    var scheme: ColorScheme? { self == .system ? nil : self == .dark ? .dark : .light }
    func title(_ zh: Bool) -> String { title(zh ? "zh-CN" : "en") }
    func title(_ language: String) -> String {
        switch self {
        case .system: return NativeStrings.text("ui.328", language: language)
        case .light: return NativeStrings.text("ui.183", language: language)
        case .dark: return NativeStrings.text("ui.091", language: language)
        }
    }
}


struct NativeOperation: Identifiable {
    let method: String
    var id: String { method }
}

@MainActor enum NativeLocalization {
    static var isolatedUXSmoke: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--ux-refinement-smoke") || ProcessInfo.processInfo.arguments.contains("--readme-screenshots")
        #else
        return false
        #endif
    }
    static let languages: [(String, String)] = [("zh-CN","简体中文"),("en","English"),("ja","日本語"),("ko","한국어"),("ru","Русский"),("es","Español"),("de","Deutsch"),("fr","Français"),("pt-BR","Português (Brasil)"),("zh-TW","繁體中文")]
    static var initialLanguage: String {
        if isolatedUXSmoke && !ProcessInfo.processInfo.arguments.contains("--readme-screenshots") { return "en" }
        if let saved = UserDefaults.standard.string(forKey: "NativeLanguage"), languages.contains(where: { $0.0 == saved }) { return saved }
        let value = Locale.preferredLanguages.first ?? "en"
        if value.hasPrefix("zh") { return value.contains("Hant") || value.contains("TW") ? "zh-TW" : "zh-CN" }
        return languages.first(where: { value.hasPrefix($0.0) })?.0 ?? "en"
    }
}
