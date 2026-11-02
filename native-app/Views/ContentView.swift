import SwiftUI

struct ContentView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        NavigationSplitView {
            SidebarView(state: state)
                .navigationSplitViewColumnWidth(min: 210, ideal: 210, max: 250)
        } detail: {
            VStack(alignment: .leading, spacing: 16) {
                if let error = state.error, state.selection != .dashboard {
                    Label(error.message(state.chinese), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityIdentifier("bridge.error")
                    Text("\(error.code) · \(error.method)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if state.stale && state.selection != .dashboard {
                    Label(state.t("以下是上次读取的数据；本次尚未完成。", "Showing the previous snapshot; this refresh has not completed."), systemImage: "clock.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.orange)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch state.selection ?? .dashboard {
                        case .dashboard: DashboardView(state: state, tasks: tasks)
                        case .environment: EnvironmentView(state: state)
                        case .fx: FXManagerView(state: state)
                        case .logs: LogsView(state: state)
                        case .settings: SettingsView(state: state)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom)
                }
                .id(state.selection)
                if tasks.busy {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(state.refreshing ? state.t("正在读取全部只读快照…", "Reading all read-only snapshots…") : state.t("操作执行中…", "Operation in progress…"))
                            .font(TacticalTypography.caption)
                        Spacer()
                        Button(state.t("取消当前操作", "Cancel current operation")) { tasks.cancel() }
                    }
                }
                if let time = state.observedAt, state.selection != .dashboard {
                    Text(state.t("快照时间：", "Snapshot: ") + time)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(TacticalSpacing.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TacticalColors(scheme: scheme).background)
            .navigationTitle("")
            .tint(TacticalColors(scheme: scheme).accent)

        }
        .sheet(item: $state.operationSelection) { item in
            LegacyOperationSheet(state: state, operation: item.method)
        }
    }
}

struct FactRow: View {
    let title: String
    let value: String
    var body: some View {
        LabeledContent(title) { Text(value).textSelection(.enabled) }
            .padding(.vertical, 5)
    }
}
