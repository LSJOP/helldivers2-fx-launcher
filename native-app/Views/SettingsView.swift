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
        Form {
            Section(state.t("界面", "Interface")) {
                Picker(state.t("语言", "Language"), selection: $state.chinese) {
                    Text("简体中文").tag(true)
                    Text("English").tag(false)
                }.accessibilityIdentifier("settings.language")
                Picker(state.t("外观", "Appearance"), selection: $state.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { item in Text(item.title(state.chinese)).tag(item) }
                }.accessibilityIdentifier("settings.appearance")
                Text(state.t("选项只在本次 App 会话生效。", "Choices apply only to this app session.")).font(.caption).foregroundStyle(.secondary)
            }
            Section("Python Bridge") {
                LabeledContent(state.t("解释器", "Interpreter"), value: state.pythonURL.lastPathComponent)
                Button(state.t("选择已有 Python…", "Choose existing Python…")) { presentation.choosingPython = true }
                Text(state.t("需要 Python 3.9 或更新版本；选择后按刷新连接。", "Requires Python 3.9 or newer. Refresh after selecting.")).font(.caption).foregroundStyle(.secondary)
                if presentation.invalidPython { Text(state.t("请选择可执行的 python3 或 python3.x 文件。", "Select an executable python3 or python3.x file.")).foregroundStyle(.red) }
            }
            Section(state.t("模式", "Mode")) {
                LabeledContent(state.t("操作权限", "Operations"), value: state.t("只读", "Read only"))
                LabeledContent(state.t("配置写入", "Configuration writes"), value: state.t("禁用", "Disabled"))
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: 420)
        .fileImporter(isPresented: $presentation.choosingPython, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            let name = url.lastPathComponent
            guard name.range(of: "^python3(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
                  FileManager.default.isExecutableFile(atPath: url.path) else { presentation.invalidPython = true; return }
            presentation.invalidPython = false; state.pythonURL = url
        }
    }
}
