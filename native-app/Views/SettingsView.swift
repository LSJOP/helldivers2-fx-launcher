import SwiftUI
import UniformTypeIdentifiers

// View-local panel presentation, never business state or persisted preferences.
private final class SettingsPresentation: ObservableObject {
    @Published var choosingPython = false
    @Published var invalidPython = false
}

struct SettingsView: View {
    @ObservedObject var state: AppState
    @StateObject private var presentation = SettingsPresentation()
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(number: "05", title: state.t("设置", "Settings"), section: Page.settings.title(state.chinese))
            TacticalPanel(number: "A", title: state.t("界面设置", "Interface"), symbol: "slider.horizontal.3") {
                Picker(state.t("语言", "Language"), selection: $state.chinese) {
                    Text("简体中文").tag(true)
                    Text("English").tag(false)
                }.accessibilityIdentifier("settings.language")
                Picker(state.t("外观", "Appearance"), selection: $state.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { item in Text(item.title(state.chinese)).tag(item) }
                }.accessibilityIdentifier("settings.appearance")
                Text(state.t("选项只在本次 App 会话生效。十种语言支持尚未恢复。", "Choices apply only to this session. Ten-language support has not been restored yet."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            TacticalPanel(number: "B", title: state.t("运行环境", "Runtime environment"), symbol: "cpu") {
                TacticalInfoRow(title: state.t("Python 解释器", "Python interpreter"), value: state.pythonURL.lastPathComponent)
                TacticalInfoRow(title: state.t("Bridge 状态", "Bridge status"), value: state.error != nil ? state.t("读取失败", "Read failed") : state.hasLoaded ? state.t("已读取 · 只读快照", "Read completed · Read-only snapshot") : state.t("尚未读取", "Not yet inspected"))
                TacticalButton(title: state.t("选择已有 Python…", "Choose existing Python…"), symbol: "folder") { presentation.choosingPython = true }
                Text(state.t("需要 Python 3.9 或更新版本；选择后按刷新连接。", "Requires Python 3.9 or newer. Refresh after selecting."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
                if presentation.invalidPython {
                    TacticalWarningBanner(text: state.t("请选择可执行的 python3 或 python3.x 文件。", "Select an executable python3 or python3.x file."), isError: true)
                }
            }
            TacticalPanel(number: "C", title: state.t("高级设置", "Advanced"), symbol: "lock.shield") {
                TacticalInfoRow(title: state.t("操作权限", "Operations"), value: state.t("只读", "Read only"))
                TacticalInfoRow(title: state.t("配置写入", "Configuration writes"), value: state.t("禁用", "Disabled"))
            }
        }
        .fileImporter(isPresented: $presentation.choosingPython, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let name = url.lastPathComponent
            guard name.range(of: "^python3(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
                  FileManager.default.isExecutableFile(atPath: url.path) else { presentation.invalidPython = true; return }
            presentation.invalidPython = false; state.pythonURL = url
        }
    }
}
