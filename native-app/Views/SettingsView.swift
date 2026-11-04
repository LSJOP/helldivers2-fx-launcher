import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.308"))
            TacticalPanel(number: "A", title: state.t("ui.166"), symbol: "slider.horizontal.3") {
                Picker(state.t("ui.170"), selection: $state.languageCode) {
                    ForEach(NativeLocalization.languages, id: \.0) { code, title in Text(title).tag(code) }
                }.accessibilityIdentifier("settings.language")
                Picker(state.t("ui.020"), selection: $state.appearance) {
                    ForEach(Appearance.allCases, id: \.self) { item in Text(item.title(state.languageCode)).tag(item) }
                }.accessibilityIdentifier("settings.appearance")
                Text(UpdateString.languageRestart.text(state.languageCode))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            TacticalPanel(number: "B", title: state.t("ui.native.runtime"), symbol: "cpu") {
                TacticalInfoRow(title: state.t("ui.native.engine"), value: state.t("ui.native.bundled"))
                TacticalInfoRow(title: state.t("ui.035"), value: state.error != nil ? state.t("ui.242") : state.hasLoaded ? state.t("ui.241") : state.t("ui.217"))
                TacticalInfoRow(title: state.t("ui.native.resources"), value: LaunchResourceSummary.text)
                Text(state.t("ui.native.noPython"))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
                Text(state.t("ui.270"))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            BuildIdentityView(state: state)
            ConfigurationBackupView(state: state)
            SSHConnectionSettingsView(state: state, tasks: state.tasks)
            CredentialManagementView(state: state, credentials: state.credentials, tasks: state.tasks)
            SoftwareUpdateView(manager: state.updates, language: state.languageCode)
            DisclosureGroup(state.t("ui.008")) { LegacyOperationsView(state: state, scope: "settings") }

        }
    }
}

// One native operation surface; all execution is delegated to AppState/NativeCoreService.
struct LegacyOperationsView: View {
    @ObservedObject var state: AppState
    let scope: String
    @ObservedObject private var tasks: TaskManager
    init(state: AppState, scope: String) {
        self.state = state; self.scope = scope; self.tasks = state.tasks
    }
    private var title: String {
        switch scope {
        case "environment": return state.t("ui.194")
        case "fx": return state.t("ui.119")
        case "logs": return state.t("ui.096")
        default: return state.t("ui.008")
        }
    }
    var body: some View {
        TacticalPanel(number: "+", title: title, symbol: "slider.horizontal.3") {
            if scope == "settings" {
                TacticalInfoRow(title: state.t("ui.226"), value: state.t("ui.249"))
                TacticalInfoRow(title: state.t("ui.073"), value: state.t("ui.233"))
            }
            if state.rows("get_legacy_catalog", "operations").isEmpty {
                Text(state.t("ui.265"))
            }
            Text(state.t("ui.001"))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(state.rows("get_legacy_catalog", "operations").filter { $0["scope"]?.text == scope && !(["check_updates","test_guest_sudo"] + GUIAction.allCases.map(\.rawValue)).contains($0["method"]?.text ?? "") }, id: \.operationID) { row in
                    let method = row["method"]?.text ?? ""
                    let requiresConsent = row["confirmation"]?.boolean == true
                    TacticalButton(title: operationTitle(method, state), symbol: requiresConsent ? "lock" : "doc.text.magnifyingglass",
                                   disabledReason: tasks.busy ? state.t("ui.016") : nil) {
                        state.operationSelection = NativeOperation(method: method)
                    }
                    .help(tasks.busy ? state.t("ui.016") : requiresConsent ? state.t("ui.222") : state.t("ui.223"))
                }
            }
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var operationID: String { self["method"]?.text ?? "unknown" }
}

@MainActor private func operationTitle(_ method: String, _ state: AppState) -> String {
    let titles: [String: String] = [
        "read_configuration": "ui.244",
        "save_configuration": "ui.234",
        "inspect_legacy_runtime": "ui.161",
        "inspect_network": "ui.160",
        "test_network": "ui.278",
        "test_ssh": "ui.329",
        "test_guest_sudo": "ui.378",
        "restore_guest_ipv6": "ui.session.restoreIPv6",
        "list_guest_ipv6_backups": "ui.session.backups",
        "connect_fx": "ui.076",
        "inspect_guest_environment": "ui.159",
        "check_fx_state": "ui.048",
        "start_fx": "ui.316",
        "start_steam": "ui.317",
        "inspect_guest": "ui.158",
        "launch_game": "ui.176",
        "preflight_launch": "ui.253",
        "observe_launch": "ui.258",
        "apply_performance": "ui.022",
        "read_performance": "ui.246",
        "apply_network_profile": "ui.024",
        "restore_network_profile": "ui.274",
        "toggle_network_check": "ui.361",
        "save_network_snapshot": "ui.295",
        "record_match": "ui.261",
        "read_network_history": "ui.245",
        "export_network_report": "ui.114",
        "export_environment_report": "ui.113",
        "check_updates": "ui.052",
        "get_legacy_catalog": "ui.150"]
    return titles[method].map { state.t($0) } ?? method
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
    @State private var configuration = "{}"
    @State private var revision = ""
    @State private var approved: [JSONValue] = []
    @State private var matchResult = "success"
    @State private var note = ""
    @State private var channel = "preview"
    @State private var inputError = false
    private var needsRoot: Bool { ["connect_fx","inspect_guest_environment","check_fx_state","start_fx","start_steam","inspect_legacy_runtime","test_ssh","test_guest_sudo","restore_guest_ipv6","inspect_guest","launch_game","preflight_launch","observe_launch","apply_performance","save_network_snapshot"].contains(operation) }
    private var needsConsent: Bool {
        state.rows("get_legacy_catalog", "operations").first { $0["method"]?.text == operation }?["confirmation"]?.boolean ?? true
    }
    private var disabledReason: String? {
        if tasks.busy { return state.t("ui.014") }
        if operation == "launch_game" && state.fxSelection.selected == nil { return state.t("ui.fx.choose") }
        if needsRoot && state.fxSelection.selected == nil { return state.t("ui.fx.choose") }
        if operation == "launch_game" && state.targetInspection["archive_files_match"]?.boolean == false { return state.t("ui.178") }
        if needsConsent && !confirmed { return state.t("ui.276") }
        return nil
    }
    private var effect: String {
        switch GUIAction(rawValue: operation) {
        case .connect: return state.t("ui.162")
        case .inspect: return state.t("ui.251")
        case .fxState: return state.t("ui.248")
        case .startFX: return state.t("ui.318")
        case .steam: return state.t("ui.078")
        default: return state.t("ui.252")
        }
    }
    private var jsonResult: String { pretty(.object(state.operationResult)) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(operationTitle(operation, state)).font(TacticalTypography.page)
                TacticalWarningBanner(text: effect)
                if operation == "restore_guest_ipv6" {
                    Text(state.guestRestorePath).font(TacticalTypography.log).textSelection(.enabled)
                }
                if operation == "apply_network_profile" {
                    TacticalWarningBanner(text: state.t("ui.342"))
                }
                if needsRoot { RuntimeTargetPanel(state: state, tasks: tasks) }
                if operation == "launch_game" {
                    DisclosureGroup(state.t("ui.ux.details")) {
                        TacticalButton(title: state.t("ui.279"), symbol: "checklist") { state.runOperation("preflight_launch") }
                            .disabled(tasks.busy || state.fxSelection.selected == nil)
                        Text(state.t("ui.195")).font(TacticalTypography.caption)
                    }
                }
                if ["connect_fx","inspect_guest_environment","start_steam","test_ssh","test_guest_sudo","restore_guest_ipv6","inspect_guest","launch_game","apply_performance","save_network_snapshot"].contains(operation) {
                    CredentialInputFields(state: state, credentials: credentials, tasks: tasks, operation: operation)
                }
                if operation == "save_configuration" {
                    Text(state.operationResult["target"]?.text ?? state.t("ui.247")).textSelection(.enabled)
                    TacticalButton(title: state.t("ui.266"), symbol: "arrow.clockwise") { state.runOperation("read_configuration") }
                    TextEditor(text: $configuration).font(TacticalTypography.log).frame(minHeight: 220)
                    Text(state.t("ui.106"))
                        .font(TacticalTypography.caption)
                }
                if operation == "record_match" {
                    Picker(state.t("ui.007"), selection: $matchResult) {
                        Text(state.t("ui.326")).tag("success")
                        Text(state.t("ui.360")).tag("timeout")
                        Text(state.t("ui.099")).tag("disconnect")
                    }
                    TextField(state.t("ui.218"), text: $note)
                }
                if operation == "check_updates" {
                    Picker(state.t("ui.047"), selection: $channel) {
                        Text(state.t("ui.232")).tag("preview"); Text(state.t("ui.314")).tag("stable")
                    }
                }
                if needsConsent {
                    Toggle(state.t("ui.153"), isOn: $confirmed)
                }
                if operation == "test_ssh" {
                    SSHDiagnosisView(state: state)
                }
                if let error = state.operationError {
                    TacticalWarningBanner(text: error.message(state.languageCode), isError: true)
                    if let change = error.details["change"] {
                        Text(pretty(change)).font(TacticalTypography.log).textSelection(.enabled)
                        TacticalButton(title: state.t("ui.025"), symbol: "checkmark.shield") {
                            approved.append(change); run()
                        }.disabled(!confirmed || tasks.busy)
                    }
                }
                if inputError { TacticalWarningBanner(text: state.t("ui.072"), isError: true) }
                if let record = state.guiRecords[operation] {
                    TacticalInfoRow(title: state.t("ui.109"), value: record.status == .running ? state.t("ui.281") : record.status == .succeeded ? state.t("ui.071") : record.status == .cancelled ? state.t("ui.039") : record.status == .timedOut ? state.t("ui.359") : state.t("ui.125"))
                }
                DisclosureGroup(state.t("ui.094")) {
                    if !state.operationResult.isEmpty { Text(jsonResult).font(TacticalTypography.log).textSelection(.enabled) }
                    if let error = state.operationError { Text(error.code + " · " + pretty(.object(error.details))).font(TacticalTypography.log).textSelection(.enabled) }
                    ForEach(Array(state.operationEvents.enumerated()), id: \.offset) { _, event in
                        HStack { Text(event["level"]?.text ?? "INFO"); Text(event["message"]?.text ?? ""); Text(event["status"]?.text ?? "") }.font(TacticalTypography.log)
                    }
                }


            }.padding(24)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                TacticalDivider()
                if let disabledReason { Text(disabledReason).font(TacticalTypography.caption).foregroundStyle(.secondary) }
                HStack {
                    TacticalButton(title: tasks.busy ? state.t("ui.282") : operation == "launch_game" ? state.t("ui.176") : state.t("ui.280"), symbol: "play.fill", primary: true, loading: tasks.busy, disabledReason: disabledReason) { run() }
                    if tasks.busy { Button(state.t("ui.038")) { state.tasks.cancel() } }
                    Spacer(minLength: 8)
                    Button(state.t("ui.069")) { dismiss() }.disabled(tasks.busy)
                }
            }.padding(16).background(.background)
        }
        .frame(minWidth: 620, idealWidth: 750, minHeight: 550, idealHeight: 700)
            .interactiveDismissDisabled(tasks.busy)
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
        if operation == "restore_guest_ipv6" { params["backup_path"] = .string(state.guestRestorePath) }
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
        DisclosureGroup(state.t("ui.session.title"), isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 10) {
                SecureField(state.t("ui.305"), text: $credentials.password)
                SecureField(state.t("ui.168"), text: $credentials.passphrase)
                if operation == "test_guest_sudo" { SecureField(state.t("ui.304"), text: $credentials.sudoPassword) }
                Text(state.t("ui.session.policy"))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
                Button(state.t("ui.067")) { state.forgetSavedCredentials() }
            }.padding(.top, 8).disabled(tasks.busy)
        }
        .onAppear { expanded = ["test_ssh","test_guest_sudo"].contains(operation) || needsInput }
        .onChange(of: state.operationError?.code) { if needsInput { expanded = true } }
    }
    private var needsInput: Bool { ["AUTH_REQUIRED","SSH_AUTH_FAILED","SUDO_AUTH_FAILED"].contains(state.operationError?.code ?? "") }
}

private struct CredentialManagementView: View {
    @ObservedObject var state: AppState
    @ObservedObject var credentials: SessionCredentialManager
    @ObservedObject var tasks: TaskManager
    var body: some View {
        TacticalPanel(number: "K", title: state.t("ui.session.title"), symbol: "key") {
            Text(state.t("ui.session.policy")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            if credentials.storageIssue { TacticalWarningBanner(text: state.t("ui.credentials.storageIssue"), isError: true) }
            ForEach(CredentialKind.allCases, id: \.self) { kind in
                VStack(alignment: .leading, spacing: 8) {
                    TacticalInfoRow(title: state.t(kind == .ssh ? "ui.session.ssh" : "ui.session.sudo"), value: status(kind))
                    if credentials.saved.contains(kind) { Text(state.t("ui.credentials.saved")).font(TacticalTypography.caption).foregroundStyle(.secondary) }
                    HStack {
                        Button(state.t(kind == .ssh ? "ui.session.updateSSH" : "ui.session.updateSudo")) {
                            credentials.update(kind)
                            state.operationSelection = NativeOperation(method: kind == .ssh ? "test_ssh" : "test_guest_sudo")
                        }
                        Button(state.t(kind == .ssh ? "ui.session.testSSH" : "ui.session.testSudo")) {
                            state.operationSelection = NativeOperation(method: kind == .ssh ? "test_ssh" : "test_guest_sudo")
                        }
                    }
                }
            }
            HStack {
                Button(state.t("ui.session.clear")) { state.forgetSavedCredentials() }
                Button(state.t("ui.session.revalidate")) { state.operationSelection = NativeOperation(method: "test_ssh") }
            }
        }.disabled(tasks.busy)
            .task { if !tasks.busy { await state.prepareCredentials() } }
    }
    private func status(_ kind: CredentialKind) -> String {
        switch credentials.status(kind) {
        case .notProvided: return state.t("ui.session.empty")
        case .provided: return state.t("ui.session.provided")
        case .verified: return state.t("ui.session.verified")
        case .failed: return state.t("ui.session.failed")
        }
    }
}


enum LaunchResourceSummary {
    static var text: String {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("launch/gvproxy-eim") else { return "—" }
        return FileManager.default.fileExists(atPath: url.path) ? "gvproxy-eim · SHA-256" : "gvproxy-eim · missing"
    }
}

private struct ConfigurationBackupView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var tasks: TaskManager
    init(state: AppState) { self.state = state; self._tasks = ObservedObject(wrappedValue: state.tasks) }
    private var backups: [[String: JSONValue]] { state.operationResult["backups"]?.array.map(\.object) ?? [] }
    var body: some View {
        TacticalPanel(number: "B2", title: state.t("ui.native.backup"), symbol: "externaldrive") {
            Text(state.t("ui.native.backupHelp")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            HStack {
                TacticalButton(title: state.t("ui.native.backupCreate"), symbol: "plus", disabledReason: tasks.busy ? state.t("ui.016") : nil) {
                    state.runOperation("backup_configuration", params: ["note": .string("manual"), "confirmed": .bool(true)])
                }
                TacticalButton(title: state.t("ui.262"), symbol: "arrow.clockwise", disabledReason: tasks.busy ? state.t("ui.016") : nil) {
                    state.runOperation("list_configuration_backups")
                }
            }
            if let path = state.operationResult["path"]?.text {
                TacticalInfoRow(title: state.t("ui.native.backupDone"), value: URL(fileURLWithPath: path).lastPathComponent)
            }
            if let revision = state.operationResult["revision"]?.text, state.operationResult["restored"]?.boolean == true {
                TacticalInfoRow(title: state.t("ui.native.restoreDone"), value: String(revision.prefix(12)))
            }
            if !backups.isEmpty {
                ForEach(backups, id: \.selfName) { row in
                    HStack {
                        Text(row["name"]?.text ?? "—").font(TacticalTypography.log).lineLimit(1)
                        Spacer(minLength: 8)
                        Button(state.t("ui.native.backupRestore")) {
                            if let path = row["path"]?.text {
                                state.runOperation("restore_configuration", params: ["backup_path": .string(path), "confirmed": .bool(true)])
                            }
                        }.disabled(tasks.busy)
                    }
                }
            } else {
                Text(state.t("ui.native.backupNone")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var selfName: String { self["name"]?.text ?? "backup" }
}

/// Read only signed bundle resources, never the development checkout.
struct BuildIdentityView: View {
    @ObservedObject var state: AppState
    private var metadata: [String: JSONValue] {
        guard let url = Bundle.main.url(forResource: "BuildMetadata", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return [:] }
        return result
    }
    private var rows: [(String, String)] {
        let info = Bundle.main.infoDictionary ?? [:]
        let unknown = state.t("ui.368")
        return [("ui.build.version", info["CFBundleShortVersionString"] as? String ?? unknown),
                ("ui.build.number", info["CFBundleVersion"] as? String ?? unknown),
                ("ui.build.commit", (metadata["commit"]?.text ?? unknown) + (metadata["source_dirty"]?.boolean == true ? " (DIRTY)" : "")),
                ("ui.build.time", metadata["built_at"]?.text ?? unknown),
                ("ui.build.core", metadata["core_version"]?.text ?? unknown),
                ("ui.build.path", Bundle.main.bundleURL.path)]
    }
    var body: some View {
        TacticalPanel(number: "i", title: state.t("ui.build.about"), symbol: "info.circle") {
            ForEach(rows, id: \.0) { row in
                TacticalInfoRow(title: state.t(row.0), value: row.1)
            }
            Button(state.t("ui.build.copy")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(rows.map { state.t($0.0) + ": " + $0.1 }.joined(separator: "\n"), forType: .string)
            }
        }
    }
}

struct SSHDiagnosisView: View {
    @ObservedObject var state: AppState
    private var facts: [String: JSONValue] {
        if !state.operationResult.isEmpty { return state.operationResult }
        if let error = state.operationError { return error.details }
        return state.operationEvents.last ?? [:]
    }
    private func value(_ field: String) -> String {
        let itemValue = ["host", "port", "username"].contains(field) ? state.sshConnectionTarget[field] ?? facts[field] : facts[field]
        guard let item = itemValue else { return state.t("ui.368") }
        if let text = item.text {
            if let stage = LaunchStage(rawValue: text) { return stage.title(state.languageCode) }
            let keys = ["unverified": "ui.368", "negotiated": "ui.241", "authenticated": "ui.241", "verified": "ui.241",
                        "Complete": "ui.071", "CheckingSSHPort": "ui.ssh.reachable", "AuthenticatingSSH": "ui.ssh.auth",
                        "VerifyingGuestIdentity": "ui.ssh.identity", "NegotiatingSSH": "ui.ssh.protocol"]
            return keys[text].map { state.t($0) } ?? text
        }
        if let number = item.integer { return String(number) }
        if let flag = item.boolean { return state.t(flag ? "ui.241" : "ui.242") }
        return state.t("ui.368")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(state.t("ui.ssh.scope")).font(TacticalTypography.caption)
            ForEach([("ui.ssh.fx", "fx_host_running"), ("ui.ssh.host", "host"),
                     ("ui.ssh.port", "port"), ("ui.ssh.user", "username"),
                     ("ui.ssh.reachable", "port_reachable"), ("ui.ssh.protocol", "protocol"),
                     ("ui.ssh.auth", "authentication"), ("ui.ssh.identity", "guest_identity"),
                     ("ui.ssh.stage", "stage")], id: \.0) { row in
                TacticalInfoRow(title: state.t(row.0), value: value(row.1))
            }
        }
    }
}

/// Edits only launcher connection metadata through the existing guarded save path.
private struct SSHConnectionSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @State private var host = ""
    @State private var port = ""
    @State private var username = ""
    @State private var revision = ""
    @State private var original: [String: JSONValue] = [:]
    @State private var saved = false
    private var patch: [String: JSONValue]? {
        guard let number = Int(port), port.allSatisfy({ $0.isASCII && $0.isNumber }), !port.isEmpty else { return nil }
        var ssh = original
        ssh["host"] = .string(host.trimmingCharacters(in: .whitespacesAndNewlines))
        ssh["port"] = .number(Double(number))
        ssh["username"] = .string(username.trimmingCharacters(in: .whitespacesAndNewlines))
        guard (try? ConfigurationService.validatedSSH(ssh)) != nil else { return nil }
        return ["host": ssh["host"]!, "port": ssh["port"]!, "username": ssh["username"]!]
    }
    private var changed: Bool {
        guard let patch else { return true }
        return patch.contains { original[$0.key] != $0.value }
    }
    var body: some View {
        TacticalPanel(number: "S", title: state.t("ui.ssh.settings"), symbol: "network") {
            Text(state.t("ui.ssh.settingsHelp")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            LabeledContent(state.t("ui.ssh.host")) {
                TextField(state.t("ui.ssh.host"), text: $host).accessibilityIdentifier("settings.ssh.host")
            }
            LabeledContent(state.t("ui.ssh.port")) {
                TextField(state.t("ui.ssh.port"), text: $port).accessibilityIdentifier("settings.ssh.port")
            }
            LabeledContent(state.t("ui.ssh.user")) {
                TextField(state.t("ui.ssh.user"), text: $username).accessibilityIdentifier("settings.ssh.user")
            }
            if !revision.isEmpty && patch == nil {
                TacticalWarningBanner(text: state.t("ui.ssh.settingsInvalid"), isError: true)
            }
            HStack {
                TacticalButton(title: state.t("ui.ssh.settingsSave"), symbol: "square.and.arrow.down", primary: true) {
                    guard let patch else { return }
                    saved = false
                    state.runOperation("save_configuration", params: ["configuration": .object(["ssh": .object(patch), "ssh_configured": .bool(true)]),
                        "expected_revision": .string(revision), "confirmed": .bool(true)])
                }.disabled(tasks.busy || revision.isEmpty || patch == nil || !changed)
                Button(state.t("ui.266")) { saved = false; state.runOperation("read_configuration") }.disabled(tasks.busy)
            }
            if saved && !changed { Text(state.t("ui.ssh.settingsSaved")).font(TacticalTypography.caption) }
            if let error = state.operationError, ["read_configuration", "save_configuration"].contains(error.method) {
                TacticalWarningBanner(text: error.message(state.languageCode), isError: true)
            }
        }
        .disabled(tasks.busy)
        .task { if !tasks.busy { state.runOperation("read_configuration") } }
        .onReceive(state.$sshConfiguration) { result in
            guard let config = result["configuration"]?.object["ssh"]?.object, let value = result["revision"]?.text else { return }
            original = config; revision = value
            host = config["host"]?.text ?? ""; port = config["port"]?.integer.map(String.init) ?? ""; username = config["username"]?.text ?? ""
        }
        .onReceive(state.$operationResult) { result in if result["saved"]?.boolean == true { saved = true } }
    }
}
