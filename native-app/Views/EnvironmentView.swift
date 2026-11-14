import SwiftUI

struct EnvironmentView: View {
    @ObservedObject var state: AppState
    private func snapshotStatus(_ method: String, fact: InspectionStatus = .uncertain) -> InspectionStatus {
        if state.refreshing { return .checking }
        if state.error?.method == method { return .failed }
        if state.stale { return .uncertain }
        return state.results[method] == nil ? .unchecked : fact
    }
    private func badge(_ status: InspectionStatus) -> some View {
        TacticalStatusBadge(text: status.title(state), tone: status.tone)
    }
    private var actionEvidence: [String: JSONValue] {
        state.guiRecords.values.filter { $0.target == state.runtimeRoot && $0.status == .succeeded && state.guiSnapshots[$0.method] != nil }.max { $0.startedAt < $1.startedAt }.flatMap { state.guiSnapshots[$0.method] } ?? [:]
    }
    private func chainStatus(_ name: String) -> InspectionStatus {
        switch name {
        case "FX": return actionEvidence["fx_host_running"]?.boolean == true ? .normal : actionEvidence["fx_host_running"]?.boolean == false ? .action : .unchecked
        case "SSH": return actionEvidence["ssh_connected"]?.boolean == true ? .normal : actionEvidence["ssh_connected"]?.boolean == false ? .action : .unchecked
        case "Guest": return actionEvidence["guest_ready"]?.boolean == true ? .normal : actionEvidence["guest_ready"]?.boolean == false ? .action : .unchecked
        case "Steam": return actionEvidence["steam_running"]?.boolean == true || (actionEvidence["steam_process_count"]?.integer ?? 0) > 0 ? .normal : actionEvidence["steam_process_count"] != nil ? .action : .unchecked
        default: return .unchecked
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.108"))
            TacticalRefreshButton(state: state, tasks: state.tasks)
            GUIOperationsPanel(state: state, tasks: state.tasks)
            TacticalButton(title: state.t("ui.ssh.test"), symbol: "network", disabledReason: state.tasks.busy ? state.t("ui.016") : nil) {
                state.operationSelection = NativeOperation(method: "test_ssh")
            }
            SteamOSNetworkPanel(state: state, tasks: state.tasks, credentials: state.credentials)
            TacticalAdaptiveLayout(minimumWidth: 140, maximumColumns: 4) {
                TacticalMetric(title: "macOS", value: state.value("get_system_info", "os_version"), symbol: "apple.logo")
                TacticalMetric(title: state.t("ui.026"), value: state.value("get_system_info", "arch"), symbol: "cpu")
                TacticalMetric(title: state.t("ui.native.runtime"), value: state.value("get_system_info", "native_runtime"), symbol: "swift")
                TacticalMetric(title: state.t("ui.164"), value: state.t("ui.152"), symbol: "square.stack.3d.up")
            }
            TacticalAdaptiveLayout(minimumWidth: 255, maximumColumns: 2) {
                TacticalPanel(number: "A", title: state.t("ui.185"), symbol: "shippingbox") {
                    ForEach(state.rows("get_dependencies", "items"), id: \.selfName) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Text(TacticalEvidence.name(row["name"]?.text ?? "—", state)).font(TacticalTypography.body)
                                Spacer(minLength: 6)
                                badge(snapshotStatus("get_dependencies", fact: InspectionStatus.dependency(row["state"]?.text)))
                            }
                            Text(TacticalEvidence.dependency(row["state"]?.text ?? "unknown", state))
                                .font(TacticalTypography.caption).foregroundStyle(.secondary)
                        }
                    }
                    if state.rows("get_dependencies", "items").isEmpty { badge(snapshotStatus("get_dependencies")) }
                    Text(state.t("ui.207"))
                        .font(TacticalTypography.caption).foregroundStyle(.secondary)
                }
                TacticalPanel(number: "B", title: state.t("ui.283"), symbol: "cpu") {
                    TacticalInfoRow(title: state.t("ui.122"), value: state.t("ui.045"))
                    TacticalInfoRow(title: state.t("ui.387"), value: state.t("ui.046"))
                    TacticalWarningBanner(text: state.t("ui.264"))
                }
            }
            DisclosureGroup(state.t("ui.009")) {
                LegacyOperationsView(state: state, scope: "environment")
            }
            TacticalPanel(number: "C", title: state.t("ui.141"), symbol: "point.3.connected.trianglepath.dotted") {
                TacticalAdaptiveLayout(minimumWidth: 95, maximumColumns: 6) {
                    ForEach(["FX", "SSH", "Guest", "Steam", "EAC", "Multiplayer"], id: \.self) { name in
                        VStack(spacing: 10) {
                            Image(systemName: name == "EAC" ? "shield.lefthalf.filled" : "shippingbox").font(.title2)
                            Text(TacticalEvidence.name(name, state)).font(TacticalTypography.body.weight(.semibold))
                            badge(chainStatus(name))
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                Text(state.t("ui.338"))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// The bridge guarantees unique dependency names; use their semantic identity.
private extension Dictionary where Key == String, Value == JSONValue {
    var selfName: String { self["name"]?.text ?? "unknown" }
}


private struct SteamOSNetworkPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @ObservedObject var credentials: SessionCredentialManager
    @State private var details = false
    private var applying: Bool { tasks.busy && state.guiRecords["apply_steamos_ipv6"]?.status == .running }
    private var reading: Bool { tasks.busy && state.guiRecords["read_steamos_ipv6"]?.status == .running }
    private var status: String { state.networkIPv6["status"]?.text ?? "unknown" }
    private var statusText: String {
        if applying { return state.t("ui.net.applying") }
        if reading { return state.t("ui.net.reading") }
        if state.networkError != nil { return state.t("ui.net.failed") }
        switch status {
        case "enabled": return state.t("ui.net.enabled")
        case "disabled": return state.t("ui.net.disabled")
        case "mixed": return state.t("ui.net.mixed")
        default: return state.t("ui.net.unknown")
        }
    }
    private func diagnosticStatus(_ status: String) -> String {
        switch status {
        case "RUNNING": return state.t("ui.net.running")
        case "PASS": return state.t("ui.net.pass")
        case "FAIL": return state.t("ui.net.fail")
        case "PAUSED": return state.t("ui.net.paused")
        case "TIMEOUT": return state.t("ui.net.timeout")
        case "UNSUPPORTED": return state.t("ui.net.unsupported")
        case "CANCELLED": return state.t("ui.net.cancelled")
        case "UNVERIFIED": return state.t("ui.net.inconclusive")
        default: return state.t("ui.net.notTested")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            TacticalPanel(number: "N1", title: state.t("ui.net.settings"), symbol: "network") {
                Toggle(isOn: Binding(get: { status == "enabled" }, set: { state.previewIPv6($0) })) {
                    VStack(alignment: .leading) {
                        Text(state.t("ui.net.ipv6"))
                        Text(statusText).font(TacticalTypography.caption).foregroundStyle(.secondary)
                    }
                }.toggleStyle(.switch).tint(Color.yellow)
                    .disabled(tasks.busy || state.networkIPv6["can_modify"]?.boolean != true)
                if status == "mixed" {
                    HStack {
                        Button(state.t("ui.net.enableAction")) { state.previewIPv6(true) }
                        Button(state.t("ui.net.disableAction")) { state.previewIPv6(false) }
                    }.disabled(tasks.busy || state.networkIPv6["can_modify"]?.boolean != true)
                }
                Text(state.t("ui.net.runtime")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                Text(state.t("ui.net.optional")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                if state.networkIPv6["changed"]?.boolean == true { Text(state.t("ui.net.applied")).font(TacticalTypography.caption).foregroundStyle(.green) }
                HStack {
                    Button(state.t("ui.net.read")) { state.runOperation("read_steamos_ipv6") }.disabled(tasks.busy)
                    Button(state.t("ui.session.restoreIPv6")) { state.previewIPv6(restore: true) }
                        .disabled(tasks.busy || state.networkBackup.isEmpty || state.networkIPv6["can_modify"]?.boolean != true)
                }
                if !(state.networkIPv6["backups"]?.array ?? []).isEmpty {
                    Picker(state.t("ui.net.backup"), selection: $state.networkBackup) {
                        ForEach(state.networkIPv6["backups"]?.array.map(\.object) ?? [], id: \.backupName) { row in
                            Text(row["name"]?.text ?? "—").tag(row["path"]?.text ?? "")
                        }
                    }.disabled(tasks.busy)
                }
                DisclosureGroup(state.t("ui.net.configDetails")) {
                    Text(state.t("ui.net.meaning")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                    ForEach((state.networkIPv6["values"]?.object ?? [:]).keys.sorted(), id: \.self) { key in
                        TacticalInfoRow(title: key, value: state.networkIPv6["values"]?.object[key]?.text ?? "—")
                    }
                }
                if let error = state.networkError {
                    TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code)
                    if let recovery = error.details["recovery_status"]?.text {
                        Text(state.t(recovery == "rolled_back" ? "ui.net.recovered" : "ui.net.recoveryNeeded")).font(TacticalTypography.caption)
                    }
                }
            }
            TacticalPanel(number: "N2", title: state.t("ui.net.diagnostics"), symbol: "waveform.path.ecg") {
                ForEach(["vm", "steam", "playfab", "udp"], id: \.self) { name in
                    let row = state.networkRows.first { $0["name"]?.text == name } ?? [:]
                    let label = name == "vm" ? state.t("ui.net.vm") : name == "steam" ? state.t("ui.net.steam") : name == "playfab" ? state.t("ui.net.playfab") : state.t("ui.net.udp")
                    HStack {
                        Text(label).font(TacticalTypography.body)
                        Spacer()
                        Text(diagnosticStatus(row["status"]?.text ?? "NOT_TESTED")).font(TacticalTypography.caption)
                        if let successes = row["successes"]?.integer, let samples = row["samples"]?.integer { Text("\(successes)/\(samples)").font(TacticalTypography.log) }
                        if case let .number(ms)? = row["ms"] { Text(String(format: "%.0f ms", ms)).font(TacticalTypography.log) }
                    }
                }
                if let error = state.networkDiagnosticError { TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code) }
                Text(state.t("ui.net.limits")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                HStack {
                    Button(state.t(state.networkRows.isEmpty ? "ui.net.start" : "ui.net.retest")) { state.runOperation("run_network_diagnostics") }.disabled(tasks.busy)
                    Button(state.t("ui.net.details")) { details.toggle() }
                    if tasks.busy && state.guiRecords["run_network_diagnostics"]?.status == .running { Button(state.t("ui.net.cancel")) { tasks.cancel() } }
                }
                if details {
                    ForEach(state.networkRows, id: \.networkName) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(row["target"]?.text ?? "—").font(TacticalTypography.caption)
                            Text(row["at"]?.text ?? "—").font(TacticalTypography.log)
                            Text(state.t("ui.net.technical") + ": " + (row["reason"]?.text ?? "—")).font(TacticalTypography.log)
                            Text(state.t(row["advice"]?.text == "scope_only" ? "ui.net.scopeAdvice" : row["advice"]?.text == "connect_or_idle" ? "ui.net.pauseAdvice" : "ui.net.retryAdvice")).font(TacticalTypography.caption)
                            if let data = try? JSONEncoder().encode(row["details"] ?? .array([])), let text = String(data: data, encoding: .utf8) {
                                Text(text).font(TacticalTypography.log).textSelection(.enabled)
                            }
                        }.padding(.vertical, 4)
                    }
                }
            }
        }
        .sheet(isPresented: $state.networkShowConfirmation, onDismiss: { state.networkPlan = [:] }) {
            VStack(alignment: .leading, spacing: 16) {
                Text(state.t("ui.net.confirm")).font(.headline)
                Text(state.t("ui.net.impact"))
                ForEach((state.networkPlan["before"]?.object ?? [:]).keys.sorted(), id: \.self) { key in
                    TacticalInfoRow(title: key, value: (state.networkPlan["before"]?.object[key]?.text ?? "?") + " → " + (state.networkPlan["after"]?.object[key]?.text ?? "?"))
                }
                SecureField(state.t("ui.session.sudo"), text: $credentials.sudoPassword)
                Text(state.t("ui.session.policy")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                HStack {
                    Button(state.t("ui.net.cancel")) { state.networkPlan = [:]; state.networkShowConfirmation = false }
                    Button(state.t("ui.net.apply")) { state.applyIPv6Plan() }.disabled(tasks.busy)
                }
            }.padding(24).frame(minWidth: 500)
        }
    }
}
private extension Dictionary where Key == String, Value == JSONValue {
    var backupName: String { self["path"]?.text ?? "unknown" }
    var networkName: String { self["name"]?.text ?? "unknown" }
}
