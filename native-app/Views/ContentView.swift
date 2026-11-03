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
                    Label(error.message(state.languageCode), systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red).textSelection(.enabled)
                        .accessibilityIdentifier("bridge.error")
                    Text("\(error.code) · \(error.method)").font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if state.stale && state.selection != .dashboard {
                    Label(state.t("ui.309"), systemImage: "clock.badge.exclamationmark")
                        .font(.callout).foregroundStyle(.orange)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch state.selection ?? .dashboard {
                        case .dashboard: DashboardView(state: state, tasks: tasks)
                        case .environment: EnvironmentView(state: state)
                        case .fx: FXManagerView(state: state)
                        case .performance: GamePerformanceView(state: state)
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
                        Text(state.inspectingTarget ? state.t("ui.ux.checking") : state.refreshing ? state.t("ui.255") : state.t("ui.225"))
                            .font(TacticalTypography.caption)
                        Spacer()
                        Button(state.t("ui.038")) { tasks.cancel() }
                    }
                }
                if let time = state.observedAt, state.selection != .dashboard {
                    Text(state.t("ui.311") + time)
                        .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(TacticalSpacing.page)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TacticalColors(scheme: scheme).background)
            .navigationTitle("")
            .tint(TacticalColors(scheme: scheme).accent)

        }
        .task(id: state.targetInspectionIdentity + (tasks.busy ? "|busy" : "|idle")) {
            state.inspectTargetIfNeeded()
        }
        .confirmationDialog(state.t("ui.075"), isPresented: Binding(get: { state.pendingAction != nil }, set: { if !$0 { state.pendingAction = nil } }), titleVisibility: .visible) {
            if let action = state.pendingAction {
                Button(state.t(action.labelKey)) { state.confirmPendingAction(action) }
            }
            Button(state.t("ui.037"), role: .cancel) { state.pendingAction = nil }
        } message: {
            Text(state.t("ui.358"))
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
