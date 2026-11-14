import SwiftUI

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    private var c: TacticalColors { TacticalColors(scheme: scheme) }
    private var unverified: String { state.t("ui.368") }
    var body: some View {
        VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
            hero
            TacticalAdaptiveLayout(minimumWidth: 120, maximumColumns: 5) {
                TacticalMetric(title: "FX", value: observed("fx_host_running"), symbol: "shippingbox")
                TacticalMetric(title: state.t("ui.144"), value: observed("ssh_connected"), symbol: "link")
                TacticalMetric(title: "Steam", value: observed("steam_running"), symbol: "play.circle")
                TacticalMetric(title: "EAC", value: unverified, symbol: "shield.lefthalf.filled")
                TacticalMetric(title: state.t("ui.191"), value: unverified, symbol: "person.2")
            }
            if state.environmentWorkflow.phase == .idle {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { launchButton; inspectButton }
                        VStack(alignment: .leading, spacing: 10) { launchButton; inspectButton }
                    }
                    if state.launchSession.current != .idle { LaunchProgressView(state: state, tasks: tasks) }
                }
            } else {
                EnvironmentWorkflowProgressView(state: state, tasks: tasks)
            }
            if let error = state.error {
                TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true)
                    .accessibilityIdentifier("bridge.error")
            }
            if state.stale { TacticalWarningBanner(text: state.t("ui.309")) }
        }.foregroundStyle(c.text).font(TacticalTypography.body)
    }
    private func observed(_ key: String) -> String {
        // A completed login step is newer evidence than the pre-launch snapshot.
        if key == "steam_running", state.environmentWorkflow.launchesGame,
           state.launchSession.evidence[.startingSteam] == "done" {
            return state.t("ui.219")
        }
        if let value = state.latestGUIEvidence[key]?.boolean { return value ? state.t("ui.219") : state.t("ui.214") }
        if key == "steam_running", let count = state.latestGUIEvidence["steam_process_count"]?.integer { return count > 0 ? state.t("ui.237") : state.t("ui.201") }
        return unverified
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HELLDIVERS 2").font(TacticalTypography.brand).foregroundStyle(c.accent).lineLimit(1).minimumScaleFactor(0.75)
                        .accessibilityIdentifier("page.title").accessibilityAddTraits(.isHeader)
                    Text(state.t("ui.brand.name")).font(.system(size: 19, weight: .bold)).foregroundStyle(c.text)
                        .lineLimit(2).minimumScaleFactor(0.75)
                }.frame(maxWidth: 380, alignment: .leading)
                HStack(spacing: 10) {
                    TacticalStatusBadge(text: state.t("ui.089"))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
            .background { SoldierBackdrop() }
        }
        .background(c.panel).overlay(Rectangle().stroke(c.line, lineWidth: 1))
        .overlay(alignment: .top) { Rectangle().fill(c.yellow).frame(height: 3) }
    }
    private var launchButton: some View {
        TacticalButton(title: state.t("ui.176"), symbol: "play.fill", primary: true, loading: tasks.busy && !state.networkDiagnosticRunning) { state.perform(.game) }
            .accessibilityIdentifier("dashboard.launch")
            .disabled(tasks.busy && !state.networkDiagnosticRunning)
    }
    private var inspectButton: some View {
        TacticalButton(title: tasks.busy ? state.t("ui.055") : state.t("ui.049"),
                       symbol: "arrow.clockwise", primary: false, loading: tasks.busy) { state.refresh() }
            .accessibilityIdentifier("dashboard.inspect")
    }
}
