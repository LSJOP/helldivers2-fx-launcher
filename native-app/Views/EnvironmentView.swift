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
            TacticalPageHeader(title: state.t("ui.108"), refreshState: state)
            GUIOperationsPanel(state: state, tasks: state.tasks)
            TacticalButton(title: state.t("ui.ssh.test"), symbol: "network", disabledReason: state.tasks.busy ? state.t("ui.016") : nil) {
                state.operationSelection = NativeOperation(method: "test_ssh")
            }
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
