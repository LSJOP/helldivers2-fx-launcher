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


struct NativeOperation: Identifiable {
    let method: String
    var id: String { method }
}

@MainActor enum NativeLocalization {
    static let languages: [(String, String)] = [("zh-CN","简体中文"),("en","English"),("ja","日本語"),("ko","한국어"),("ru","Русский"),("es","Español"),("de","Deutsch"),("fr","Français"),("pt-BR","Português (Brasil)"),("zh-TW","繁體中文")]
    static var initialLanguage: String {
        if let saved = UserDefaults.standard.string(forKey: "NativeLanguage"), languages.contains(where: { $0.0 == saved }) { return saved }
        let value = Locale.preferredLanguages.first ?? "en"
        if value.hasPrefix("zh") { return value.contains("Hant") || value.contains("TW") ? "zh-TW" : "zh-CN" }
        return languages.first(where: { value.hasPrefix($0.0) })?.0 ?? "en"
    }
    private static let catalogs: [String: [String: String]] = {
        guard let base = Bundle.main.resourceURL else { return [:] }
        func read(_ code: String) -> [String: Any] {
            guard let data = try? Data(contentsOf: base.appendingPathComponent("locales/" + code + ".json")),
                  let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return value
        }
        let english = read("en")["strings"] as? [String: String] ?? [:]
        var result: [String: [String: String]] = [:]
        for (code, _) in languages {
            let data = read(code)
            var map = data["messages"] as? [String: String] ?? [:]
            let strings = data["strings"] as? [String: String] ?? [:]
            for (key, value) in english { if let localized = strings[key] { map[value] = localized } }
            if let extra = base.appendingPathComponent("native-locales.json") as URL?,
               let bytes = try? Data(contentsOf: extra),
               let all = try? JSONSerialization.jsonObject(with: bytes) as? [String: [String: String]] {
                map.merge(all[code] ?? [:]) { _, new in new }
            }
            result[code] = map
        }
        return result
    }()
    static func text(_ zh: String, _ en: String, language: String) -> String {
        if language == "zh-CN" { return zh }
        if language == "en" { return en }
        return catalogs[language]?[en] ?? en
    }
}
