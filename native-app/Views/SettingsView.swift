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
            TacticalPageHeader(number: "05", title: state.t("设置", "Settings"), section: state.pageTitle(.settings))
            TacticalPanel(number: "A", title: state.t("界面设置", "Interface"), symbol: "slider.horizontal.3") {
                Picker(state.t("语言", "Language"), selection: $state.languageCode) {
                    ForEach(NativeLocalization.languages, id: \.0) { code, title in Text(title).tag(code) }
                }.accessibilityIdentifier("settings.language")
                Picker(state.t("外观", "Appearance"), selection: $state.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { item in Text(item.title(state.chinese)).tag(item) }
                }.accessibilityIdentifier("settings.appearance")
                Text(UpdateString.languageRestart.text(state.languageCode))
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
            LegacyOperationsView(state: state, scope: "settings")
            SoftwareUpdateView(manager: state.updates, language: state.languageCode)
            TacticalPanel(number: "C", title: state.t("高级设置", "Advanced"), symbol: "lock.shield") {
                TacticalInfoRow(title: state.t("操作权限", "Operations"), value: state.t("默认只读 · 逐操作确认", "Read-only default · Per-action consent"))
                TacticalInfoRow(title: state.t("配置写入", "Configuration writes"), value: state.t("需预览与确认", "Preview and confirmation required"))
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

// One native operation surface; all execution is delegated to AppState/BridgeService.
struct LegacyOperationsView: View {
    @ObservedObject var state: AppState
    let scope: String
    var body: some View {
        TacticalPanel(number: "+", title: state.t("原脚本功能", "Legacy capabilities"), symbol: "slider.horizontal.3") {
            if state.rows("get_legacy_catalog", "operations").isEmpty {
                Text(state.t("请刷新以读取后端能力。", "Refresh to read backend capabilities."))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170))], spacing: 8) {
                ForEach(state.rows("get_legacy_catalog", "operations").filter { $0["scope"]?.text == scope && $0["method"]?.text != "check_updates" }, id: \.operationID) { row in
                    let method = row["method"]?.text ?? ""
                    TacticalButton(title: operationTitle(method, state), symbol: row["confirmation"]?.boolean == true ? "lock.open" : "doc.text.magnifyingglass") {
                        state.operationSelection = NativeOperation(method: method)
                    }.disabled(state.tasks.busy)
                }
            }
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var operationID: String { self["method"]?.text ?? "unknown" }
}

@MainActor private func operationTitle(_ method: String, _ state: AppState) -> String {
    let titles: [String: (String, String)] = [
        "read_configuration": ("读取启动配置", "Read launcher configuration"),
        "save_configuration": ("预览并保存配置", "Preview and save configuration"),
        "inspect_legacy_runtime": ("详细运行环境检查", "Inspect legacy runtime"),
        "inspect_network": ("查看本机网络", "Inspect host network"),
        "test_network": ("运行网络测试", "Run network test"),
        "test_ssh": ("测试 SSH 连接", "Test SSH connection"),
        "inspect_guest": ("读取 Guest / Steam", "Inspect Guest / Steam"),
        "launch_game": ("启动 HELLDIVERS 2", "Launch HELLDIVERS 2"),
        "preflight_launch": ("启动前只读检查", "Read-only launch preflight"),
        "observe_launch": ("只读复查游戏进程", "Recheck game process"),
        "apply_performance": ("应用原性能配置", "Apply legacy performance profile"),
        "read_performance": ("查看性能配置", "Read performance configuration"),
        "apply_network_profile": ("应用有线网络方案", "Apply wired network profile"),
        "restore_network_profile": ("恢复网络方案", "Restore network profile"),
        "toggle_network_check": ("切换启动前网络检查", "Toggle prelaunch network check"),
        "save_network_snapshot": ("保存网络快照", "Save network snapshot"),
        "record_match": ("记录匹配结果", "Record match outcome"),
        "read_network_history": ("查看网络历史", "Read network history"),
        "export_network_report": ("导出网络报告", "Export network report"),
        "export_environment_report": ("导出环境报告", "Export environment report"),
        "check_updates": ("检查官方更新", "Check official updates"),
        "get_legacy_catalog": ("帮助与功能清单", "Help and capability catalog")]
    let value = titles[method] ?? (method, method)
    return state.t(value.0, value.1)
}

struct LegacyOperationSheet: View {
    @ObservedObject var state: AppState
    let operation: String
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var choosingRoot = false
    @State private var password = ""
    @State private var passphrase = ""
    @State private var sudoPassword = ""
    @State private var configuration = "{}"
    @State private var revision = ""
    @State private var approved: [JSONValue] = []
    @State private var matchResult = "success"
    @State private var note = ""
    @State private var channel = "preview"
    @State private var inputError = false
    private var needsRoot: Bool { ["inspect_legacy_runtime","test_ssh","inspect_guest","launch_game","preflight_launch","observe_launch","apply_performance","save_network_snapshot"].contains(operation) }
    private var needsConsent: Bool {
        state.rows("get_legacy_catalog", "operations").first { $0["method"]?.text == operation }?["confirmation"]?.boolean ?? true
    }
    private var jsonResult: String { pretty(.object(state.operationResult)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(operationTitle(operation, state)).font(TacticalTypography.page)
                TacticalWarningBanner(text: state.t("只读是默认模式。此处仅执行你主动选择的功能；启动或配置可能启动 FX/Steam、连接 SSH、写入配置或修改系统网络。取消只停止当前操作，不承诺关闭已启动的游戏。", "Read-only is the default. This panel runs only your selected action. Launch/configuration can start FX/Steam, connect SSH, write configuration or change host networking. Cancellation stops the current operation; it does not promise to close a running game."))
                if operation == "apply_network_profile" {
                    TacticalWarningBanner(text: state.t("该原脚本方案会在确认有线网络与代理可用后关闭 Wi-Fi，并保存恢复记录。请先核对下方具体变更。", "The legacy profile disables Wi-Fi after checking wired connectivity and the proxy, and records recovery state. Review the exact change below."))
                }
                if needsRoot {
                    TextField(state.t("已有旧启动器完整目录", "Existing full legacy launcher directory"), text: $state.runtimeRoot)
                        .disabled(state.tasks.busy)
                    TacticalButton(title: state.t("选择目录…", "Choose directory…"), symbol: "folder") { choosingRoot = true }.disabled(state.tasks.busy)
                    Text(state.t("不会下载或移动 FX。目录内 JS 和 wrapper 必须与归档一致，原 Core 的二进制哈希与目标检查仍然生效。", "No FX download or relocation. JS and wrapper must match the archive; original Core binary-hash and target checks remain active."))
                        .font(TacticalTypography.caption)
                }
                if operation == "launch_game" {
                    TacticalButton(title: state.t("先做只读预检", "Run read-only preflight"), symbol: "checklist") { state.runOperation("preflight_launch") }
                        .disabled(state.tasks.busy || state.runtimeRoot.isEmpty)
                }
                if ["test_ssh","inspect_guest","launch_game","apply_performance","save_network_snapshot"].contains(operation) {
                    SecureField(state.t("本次 SSH 密码（可留空使用已有认证）", "Session SSH password (optional with existing authentication)"), text: $password)
                    SecureField(state.t("本次密钥口令", "Session key passphrase"), text: $passphrase)
                    SecureField(state.t("本次 Guest sudo 密码", "Session Guest sudo password"), text: $sudoPassword)
                    Text(state.t("秘密只通过进程 stdin 传递；是否使用钥匙串由原 SSH 配置控制。", "Secrets are sent only through process stdin. The original SSH setting controls Keychain use."))
                        .font(TacticalTypography.caption)
                }
                if operation == "save_configuration" {
                    Text(state.operationResult["target"]?.text ?? state.t("先读取目标配置", "Read target configuration first")).textSelection(.enabled)
                    TacticalButton(title: state.t("重新读取配置", "Reload configuration"), symbol: "arrow.clockwise") { state.runOperation("read_configuration") }
                    TextEditor(text: $configuration).font(TacticalTypography.log).frame(minHeight: 220)
                    Text(state.t("仅编辑已显示的非秘密字段。未知原字段保留；原内容发生变化将拒绝保存，并在原目录建立备份。", "Edit only the displayed non-secret fields. Existing unknown fields are preserved; concurrent changes reject saving. A backup is created in the original directory."))
                        .font(TacticalTypography.caption)
                }
                if operation == "record_match" {
                    Picker(state.t("实际观察到的结果", "Actually observed result"), selection: $matchResult) {
                        Text(state.t("成功", "Success")).tag("success")
                        Text(state.t("超时", "Timeout")).tag("timeout")
                        Text(state.t("断线", "Disconnect")).tag("disconnect")
                    }
                    TextField(state.t("备注（自动脱敏）", "Note (redacted)"), text: $note)
                }
                if operation == "check_updates" {
                    Picker(state.t("通道", "Channel"), selection: $channel) {
                        Text("Preview").tag("preview"); Text("Stable").tag("stable")
                    }
                }
                if needsConsent {
                    Toggle(state.t("我允许本次明确选择的操作，并知悉上方影响范围", "I authorize this selected action and understand the effects above"), isOn: $confirmed)
                }
                if let error = state.operationError {
                    TacticalWarningBanner(text: error.code + " · " + (error.details["summary"]?.text ?? error.message(state.chinese)), isError: true)
                    if let change = error.details["change"] {
                        Text(pretty(change)).font(TacticalTypography.log).textSelection(.enabled)
                        TacticalButton(title: state.t("确认这项具体变更并继续", "Approve this exact change and continue"), symbol: "checkmark.shield") {
                            approved.append(change); run()
                        }.disabled(!confirmed || state.tasks.busy)
                    }
                }
                if inputError { TacticalWarningBanner(text: state.t("配置必须为有效 JSON 对象，且已读取当前修订。", "Configuration must be a valid JSON object with a loaded revision."), isError: true) }
                if !state.operationResult.isEmpty {
                    Text(jsonResult).font(TacticalTypography.log).textSelection(.enabled)
                }
                ForEach(Array(state.operationEvents.enumerated()), id: \.offset) { _, event in
                    HStack {
                        Text(event["level"]?.text ?? "INFO").font(TacticalTypography.log)
                        Text(event["message"]?.text ?? "")
                        Text(event["status"]?.text ?? "").font(TacticalTypography.log)
                    }
                }
                HStack {
                    TacticalButton(title: state.tasks.busy ? state.t("执行中…", "Running…") : state.t("执行所选操作", "Run selected action"), symbol: "play.fill", primary: true, loading: state.tasks.busy) { run() }
                        .disabled((needsConsent && !confirmed) || (needsRoot && state.runtimeRoot.isEmpty))
                    if state.tasks.busy { Button(state.t("取消当前操作", "Cancel current operation")) { state.tasks.cancel() } }
                    Button(state.t("关闭", "Close")) { dismiss() }.disabled(state.tasks.busy)
                }
            }.padding(24)
        }.frame(minWidth: 620, idealWidth: 750, minHeight: 550, idealHeight: 700)
            .interactiveDismissDisabled(state.tasks.busy)
            .fileImporter(isPresented: $choosingRoot, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { state.runtimeRoot = url.path }
            }
            .onReceive(state.$operationResult) { result in
                if let value = result["configuration"], let current = result["revision"]?.text {
                    configuration = pretty(value); revision = current
                }
            }
            .task { if operation == "save_configuration" { state.runOperation("read_configuration") } }
    }
    private func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
    }
    private func run() {
        inputError = false
        var params: [String: JSONValue] = [:]
        if needsConsent { params["confirmed"] = .bool(confirmed) }
        if !password.isEmpty { params["password"] = .string(password) }
        if !passphrase.isEmpty { params["passphrase"] = .string(passphrase) }
        if !sudoPassword.isEmpty { params["sudo_password"] = .string(sudoPassword) }
        params["approved_changes"] = .array(approved)
        if operation == "save_configuration" {
            guard !revision.isEmpty, let data = configuration.data(using: .utf8), let value = try? JSONDecoder().decode(JSONValue.self, from: data), case .object = value else { inputError = true; return }
            params["configuration"] = value; params["expected_revision"] = .string(revision)
        }
        if operation == "record_match" { params["match_result"] = .string(matchResult); params["note"] = .string(note) }
        if operation == "check_updates" { params["channel"] = .string(channel) }
        state.runOperation(operation, params: params)
    }
}
