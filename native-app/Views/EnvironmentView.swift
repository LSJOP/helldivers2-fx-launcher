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
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("运行环境检测", "Environment inspection"), refreshState: state)
            TacticalAdaptiveLayout(minimumWidth: 140, maximumColumns: 4) {
                TacticalMetric(title: "macOS", value: state.value("get_system_info", "os_version"), symbol: "apple.logo")
                TacticalMetric(title: state.t("架构", "Architecture"), value: state.value("get_system_info", "arch"), symbol: "cpu")
                TacticalMetric(title: "Python", value: state.value("get_system_info", "python"), symbol: "terminal")
                TacticalMetric(title: state.t("检测范围", "Inspection scope"), value: state.t("本机只读快照", "Host read-only snapshot"), symbol: "square.stack.3d.up")
            }
            TacticalAdaptiveLayout(minimumWidth: 255, maximumColumns: 2) {
                TacticalPanel(number: "A", title: state.t("本地依赖", "Local dependencies"), symbol: "shippingbox") {
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
                    Text(state.t("正常仅表示该 Python 已执行 Bridge；工具文件存在仍无法确认连接或服务就绪。", "Normal means this Python executed the Bridge. Tool files alone do not confirm connectivity or service readiness."))
                        .font(TacticalTypography.caption).foregroundStyle(.secondary)
                }
                TacticalPanel(number: "B", title: state.t("运行组件", "Runtime components"), symbol: "cpu") {
                    TacticalInfoRow(title: state.t("FX 运行时", "FX runtime"), value: state.t("无法确认 · 只读快照未探测进程", "Cannot confirm · Snapshot does not probe processes"))
                    TacticalInfoRow(title: state.t("gvproxy 运行时", "gvproxy runtime"), value: state.t("无法确认 · 只读快照未探测服务", "Cannot confirm · Snapshot does not probe services"))
                    TacticalWarningBanner(text: state.t("刷新不会启动 FX 或连接 Guest。使用网络与连接工具主动检查；启动记录不等于当前实时状态。", "Refresh does not start FX or connect to Guest. Use the connection tools for explicit checks; launch history is not current live state."))
                }
            }
            LegacyOperationsView(state: state, scope: "environment")
            TacticalPanel(number: "C", title: state.t("游戏运行链路 · 检测范围", "Game runtime chain · inspection scope"), symbol: "point.3.connected.trianglepath.dotted") {
                TacticalAdaptiveLayout(minimumWidth: 95, maximumColumns: 6) {
                    ForEach(["FX", "SSH", "Guest", "Steam", "EAC", "Multiplayer"], id: \.self) { name in
                        VStack(spacing: 10) {
                            Image(systemName: name == "EAC" ? "shield.lefthalf.filled" : "shippingbox").font(.title2)
                            Text(TacticalEvidence.name(name, state)).font(TacticalTypography.body.weight(.semibold))
                            badge(.unchecked)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
                Text(state.t("只读快照不检查此链路。连接工具的检测结果在操作面板显示；游戏启动的阶段证据在总览显示。安装文件、进程、Guest 就绪、游戏主菜单、EAC 与联机均为独立证据。", "The read-only snapshot does not probe this chain. Connection results appear in the operation panel; launch-stage evidence appears on Dashboard. Installation files, processes, Guest readiness, the game menu, EAC and multiplayer require separate evidence."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// The bridge guarantees unique dependency names; use their semantic identity.
private extension Dictionary where Key == String, Value == JSONValue {
    var selfName: String { self["name"]?.text ?? "unknown" }
}
