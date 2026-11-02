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
            TacticalPageHeader(title: state.t("设置", "Settings"))
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
                Text(state.t("需要 Python 3.9 或更新版本；选择后按 ⌘R 读取全部只读快照。", "Requires Python 3.9 or newer. Press ⌘R after selecting to reload all read-only snapshots."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
                if presentation.invalidPython {
                    TacticalWarningBanner(text: state.t("请选择可执行的 python3 或 python3.x 文件。", "Select an executable python3 or python3.x file."), isError: true)
                }
            }
            CredentialManagementView(state: state, credentials: state.credentials, tasks: state.tasks)
            SoftwareUpdateView(manager: state.updates, language: state.languageCode)
            LegacyOperationsView(state: state, scope: "settings")

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
    @ObservedObject private var tasks: TaskManager
    init(state: AppState, scope: String) {
        self.state = state; self.scope = scope; self.tasks = state.tasks
    }
    private var title: String {
        switch scope {
        case "environment": return state.t("网络与连接工具", "Network and connection tools")
        case "fx": return state.t("FX 诊断工具", "FX diagnostics")
        case "logs": return state.t("诊断报告", "Diagnostic reports")
        default: return state.t("高级配置", "Advanced configuration")
        }
    }
    var body: some View {
        TacticalPanel(number: "+", title: title, symbol: "slider.horizontal.3") {
            if scope == "settings" {
                TacticalInfoRow(title: state.t("操作权限", "Operations"), value: state.t("默认只读 · 逐操作确认", "Read-only default · Per-action consent"))
                TacticalInfoRow(title: state.t("配置写入", "Configuration writes"), value: state.t("需预览与确认", "Preview and confirmation required"))
            }
            if state.rows("get_legacy_catalog", "operations").isEmpty {
                Text(state.t("请刷新以读取后端能力。", "Refresh to read backend capabilities."))
            }
            Text(state.t("锁标记表示执行前需要确认；打开面板不会执行操作。只读功能无需变更授权。", "A lock marks actions requiring confirmation before execution. Opening a panel runs nothing. Read-only tools need no change approval."))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(state.rows("get_legacy_catalog", "operations").filter { $0["scope"]?.text == scope && !["check_updates","test_guest_sudo"].contains($0["method"]?.text ?? "") }, id: \.operationID) { row in
                    let method = row["method"]?.text ?? ""
                    let requiresConsent = row["confirmation"]?.boolean == true
                    TacticalButton(title: operationTitle(method, state), symbol: requiresConsent ? "lock" : "doc.text.magnifyingglass",
                                   disabledReason: tasks.busy ? state.t("已有操作执行中，请等待完成或在操作面板取消。", "Another operation is running. Wait or cancel it in the operation panel.") : nil) {
                        state.operationSelection = NativeOperation(method: method)
                    }
                    .help(tasks.busy ? state.t("已有操作执行中，请等待完成或在操作面板取消。", "Another operation is running. Wait or cancel it in the operation panel.") : requiresConsent ? state.t("打开操作面板：执行前需确认具体影响范围。", "Open the operation panel; review the exact scope before confirming execution.") : state.t("打开只读检查面板；不会自动执行。", "Open the read-only inspection panel. It does not run automatically."))
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
        "test_guest_sudo": ("验证 Guest sudo 密码", "Verify Guest sudo password"),
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
    @ObservedObject private var credentials: SessionCredentialManager
    @ObservedObject private var tasks: TaskManager
    init(state: AppState, operation: String) {
        self.state = state; self.operation = operation
        self._credentials = ObservedObject(wrappedValue: state.credentials)
        self._tasks = ObservedObject(wrappedValue: state.tasks)
    }
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    @State private var choosingRoot = false
    @State private var configuration = "{}"
    @State private var revision = ""
    @State private var approved: [JSONValue] = []
    @State private var matchResult = "success"
    @State private var note = ""
    @State private var channel = "preview"
    @State private var inputError = false
    private var needsRoot: Bool { ["inspect_legacy_runtime","test_ssh","test_guest_sudo","inspect_guest","launch_game","preflight_launch","observe_launch","apply_performance","save_network_snapshot"].contains(operation) }
    private var needsConsent: Bool {
        state.rows("get_legacy_catalog", "operations").first { $0["method"]?.text == operation }?["confirmation"]?.boolean ?? true
    }
    private var disabledReason: String? {
        if tasks.busy { return state.t("当前操作执行中", "An operation is running") }
        if needsRoot && state.runtimeRoot.isEmpty { return state.t("请先选择启动器目录", "Choose a launcher directory first") }
        if needsConsent && !confirmed { return state.t("请先核对影响范围并勾选授权", "Review the scope and grant authorization first") }
        return nil
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
                        .disabled(tasks.busy)
                    TacticalButton(title: state.t("选择目录…", "Choose directory…"), symbol: "folder") { choosingRoot = true }.disabled(tasks.busy)
                    Text(state.t("不会下载或移动 FX。目录内 JS 和 wrapper 必须与归档一致，原 Core 的二进制哈希与目标检查仍然生效。", "No FX download or relocation. JS and wrapper must match the archive; original Core binary-hash and target checks remain active."))
                        .font(TacticalTypography.caption)
                }
                if operation == "launch_game" {
                    TacticalButton(title: state.t("先做只读预检", "Run read-only preflight"), symbol: "checklist") { state.runOperation("preflight_launch") }
                        .disabled(tasks.busy || state.runtimeRoot.isEmpty)
                }
                if ["test_ssh","test_guest_sudo","inspect_guest","launch_game","apply_performance","save_network_snapshot"].contains(operation) {
                    CredentialInputFields(state: state, credentials: credentials, tasks: tasks, operation: operation)
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
                        }.disabled(!confirmed || tasks.busy)
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

            }.padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TacticalDivider()
                if let disabledReason { Text(disabledReason).font(TacticalTypography.caption).foregroundStyle(.secondary) }
                HStack {
                    TacticalButton(title: tasks.busy ? state.t("执行中…", "Running…") : state.t("执行所选操作", "Run selected action"), symbol: "play.fill", primary: true, loading: tasks.busy, disabledReason: disabledReason) { run() }
                    if tasks.busy { Button(state.t("取消当前操作", "Cancel current operation")) { state.tasks.cancel() } }
                    Spacer(minLength: 8)
                    Button(state.t("关闭", "Close")) { dismiss() }.disabled(tasks.busy)
                }
            }.padding(16).background(.background)
        }
        .frame(minWidth: 620, idealWidth: 750, minHeight: 550, idealHeight: 700)
            .interactiveDismissDisabled(tasks.busy)
            .fileImporter(isPresented: $choosingRoot, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { state.runtimeRoot = url.path }
            }
            .onReceive(state.$operationResult) { result in
                if let value = result["configuration"], let current = result["revision"]?.text {
                    configuration = pretty(value); revision = current
                }
            }
            .task {
                if operation == "save_configuration" { state.runOperation("read_configuration") }
                else if !tasks.busy { await state.prepareCredentials() }
            }
    }
    private func pretty(_ value: JSONValue) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? String(data: encoder.encode(value), encoding: .utf8)) ?? "{}"
    }
    private func run() {
        inputError = false
        var params: [String: JSONValue] = [:]
        if needsConsent { params["confirmed"] = .bool(confirmed) }
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


private struct CredentialInputFields: View {
    @ObservedObject var state: AppState
    @ObservedObject var credentials: SessionCredentialManager
    @ObservedObject var tasks: TaskManager
    let operation: String
    @State private var expanded = false
    var body: some View {
        DisclosureGroup(state.t("凭据（已有连接／免密码 sudo 可留空）", "Credentials (optional with an existing connection / passwordless sudo)"), isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField(state.t("本次 SSH 密码", "Session SSH password"), text: $credentials.password)
                Toggle(state.t("记住 SSH 密码（认证成功后保存）", "Remember SSH password after successful authentication"), isOn: Binding(get: { credentials.rememberSSH }, set: { credentials.setRemember(.ssh, $0) }))
                SecureField(state.t("本次密钥口令（仅保留在会话）", "Key passphrase (session only)"), text: $credentials.passphrase)
                SecureField(state.t("本次 Guest sudo 密码", "Session Guest sudo password"), text: $credentials.sudoPassword)
                Toggle(state.t("记住 Guest sudo 密码（认证成功后保存）", "Remember Guest sudo password after successful authentication"), isOn: Binding(get: { credentials.rememberSudo }, set: { credentials.setRemember(.sudo, $0) }))
                Text(state.t("默认仅存本次会话。勾选后，仅经实际密码认证的对应凭据保存到本 App 专用钥匙串记录；两种密码互不替代。自动读取不弹出授权窗口，访问受限时请手动输入。密钥口令不持久化。", "Session only by default. When selected, each password is saved to this App’s Keychain records only after an actual password challenge succeeds. SSH and sudo remain separate. Automatic reads never request authorization UI; enter manually if access is restricted. Key passphrases are not saved."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
                CredentialVaultNotice(state: state, credentials: credentials)
                Button(state.t("清除本次会话凭据", "Clear session credentials")) { credentials.clear() }
            }.padding(.top, 8).disabled(tasks.busy)
        }
        .onAppear { expanded = ["test_ssh","test_guest_sudo"].contains(operation) || needsInput }
        .onChange(of: state.operationError?.code) { if needsInput { expanded = true } }
    }
    private var needsInput: Bool { ["AUTH_REQUIRED","SSH_AUTH_FAILED","SUDO_AUTH_FAILED"].contains(state.operationError?.code ?? "") }
}

private struct CredentialVaultNotice: View {
    @ObservedObject var state: AppState
    @ObservedObject var credentials: SessionCredentialManager
    var body: some View {
        if let error = credentials.vaultError {
            Text(message(error)).font(TacticalTypography.caption).foregroundStyle(.orange)
        }
    }
    private func message(_ error: CredentialVaultError) -> String {
        switch error {
        case .locked: return state.t("登录钥匙串已锁定，尚未解锁；自动读取已停止，请自行解锁或使用本次会话输入。", "The login Keychain is locked; it has not been unlocked. Automatic reads stopped. Unlock it yourself or use session input.")
        case .permission: return state.t("钥匙串访问授权受限（或已停用自动读取），不等于钥匙串解锁失败。可手动输入，或主动点击下方授权读取；应用身份／签名变化可能需要系统确认。", "Keychain access requires authorization (or automatic reads are disabled); this is distinct from an unlock failure. Enter manually or explicitly authorize access below. App identity/signing changes can require system confirmation.")
        default: return state.t("安全存储当前不可用；凭据仍仅存于会话内存，未降级为文件保存。", "Secure storage is unavailable. Credentials remain in session memory; no file-storage fallback was used.")
        }
    }
}

private struct CredentialManagementView: View {
    @ObservedObject var state: AppState
    @ObservedObject var credentials: SessionCredentialManager
    @ObservedObject var tasks: TaskManager
    @State private var clearing: CredentialKind?
    @State private var clearAll = false
    var body: some View {
        TacticalPanel(number: "K", title: state.t("凭据管理", "Credential management"), symbol: "key") {
            Text(state.t("仅管理当前启动目录与配置对应的记录；更新所存凭据不修改 Guest 账户密码；验证后勾选才保存。保存目标目录便于下次复用，不保存密码到偏好设置。", "Manage records for the selected launcher directory and configuration. Updating stored credentials does not change the Guest account password. Saving requires verification and opt-in. The launcher directory is retained for reuse; passwords are never stored in preferences."))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            ForEach(CredentialKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 8) {
                    TacticalInfoRow(title: kind == .ssh ? state.t("SSH 密码", "SSH password") : state.t("Guest sudo 密码", "Guest sudo password"), value: status(kind))
                    HStack {
                        Button(state.t("更新密码", "Update password")) {
                            credentials.update(kind)
                            state.operationSelection = NativeOperation(method: kind == .ssh ? "test_ssh" : "test_guest_sudo")
                        }
                        Button(state.t("清除密码", "Clear password")) { clearing = kind }
                    }
                }
            }
            CredentialVaultNotice(state: state, credentials: credentials)
            Button(state.t("授权读取当前目标凭据…", "Authorize reading this target’s credentials…")) { Task { await state.prepareCredentials(interactive: true) } }
            Button(state.t("清除所有已保存凭据…", "Clear all saved credentials…")) { clearAll = true }
        }
        .disabled(tasks.busy)
        .task(id: state.runtimeRoot) { if !tasks.busy { await state.prepareCredentials() } }
        .confirmationDialog(state.t("清除当前目标的这项密码？同时清除本次会话副本。", "Clear this password for the current target and its session copy?"), isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } })) {
            if let kind = clearing { Button(state.t("确认清除", "Confirm clear"), role: .destructive) { Task { await credentials.remove(kind) }; clearing = nil } }
        }
        .confirmationDialog(state.t("清除本 App 所有已保存凭据？不会删除旧脚本或其他应用的钥匙串记录。", "Clear all credentials saved by this App? Legacy-script and other apps’ Keychain records are untouched."), isPresented: $clearAll) {
            Button(state.t("清除所有已保存凭据", "Clear all saved credentials"), role: .destructive) { Task { await credentials.removeAll() } }
        }
    }
    private func status(_ kind: CredentialKind) -> String {
        if credentials.vaultError != nil { return state.t("无法确认 · 自动复用受限", "Cannot confirm · Automatic reuse restricted") }
        if credentials.rejected.contains(kind) { return state.t("认证失效／已停止复用", "Authentication rejected / reuse stopped") }
        return credentials.saved.contains(kind) ? state.t("已保存 · 当前目标", "Saved · Current target") : state.t("未保存", "Not saved")
    }
}
