import SwiftUI

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    @State private var showingOverview = false
    private var c: TacticalColors { TacticalColors(scheme: scheme) }
    var body: some View {
        Group {
            if state.environmentWorkflow.launchesGame && state.environmentWorkflow.phase != .idle && !showingOverview {
                launchPreparation
            } else {
                overview
            }
        }
        .foregroundStyle(c.text).font(TacticalTypography.body)
        .onChange(of: state.environmentWorkflow.taskID) { _, _ in
            if state.environmentWorkflow.launchesGame { showingOverview = false }
        }
    }
    private var launchPreparation: some View {
        VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
            TacticalPageHeader(title: state.t("ui.176"))
            TacticalFlowArtwork(asset: "MOTR7Soldier") {
                VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
                    EnvironmentWorkflowProgressView(state: state, tasks: tasks, showStepsInline: true, returnToDashboard: { showingOverview = true })
                    TacticalButton(title: state.t("ui.092"), symbol: "square.grid.2x2", primary: false) { showingOverview = true }
                }
            }
            if let error = state.error { TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true) }
            if state.stale { TacticalWarningBanner(text: state.t("ui.309")) }
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
            hero
            TacticalAdaptiveLayout(minimumWidth: 120, maximumColumns: 5) {
                statusCard("FX", "shippingbox", "fx_host_running", .startingFX)
                statusCard(state.t("ui.net.vm"), "link", "ssh_connected", .waitingForGuest)
                statusCard("Steam", "play.circle", "steam_running", .startingSteam)
                statusCard("EAC", "shield.lefthalf.filled", "eac", .checkingEAC)
                statusCard(state.t("ui.191"), "person.2", "multiplayer", nil)
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
                if state.environmentWorkflow.launchesGame {
                    TacticalButton(title: state.t("ui.088"), symbol: "list.bullet.rectangle", primary: false) { showingOverview = false }
                }
                EnvironmentWorkflowProgressView(state: state, tasks: tasks)
            }
            if let error = state.error {
                TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true)
                    .accessibilityIdentifier("bridge.error")
            }
            if state.stale { TacticalWarningBanner(text: state.t("ui.309")) }
        }
    }
    private func statusCard(_ title: String, _ symbol: String, _ key: String, _ stage: LaunchStage?) -> some View {
        let status = DashboardStatus.resolve(key: key, stage: stage, session: state.launchSession,
                                             workflow: state.environmentWorkflow, evidence: state.latestGUIEvidence,
                                             stale: state.stale)
        return DashboardStatusCard(title: title, value: state.t(status.textKey), symbol: symbol, tone: status.tone)
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
        TacticalButton(title: state.t("ui.176"), symbol: "play.fill", primary: true, loading: tasks.busy && !state.networkDiagnosticRunning) { showingOverview = false; state.perform(.game) }
            .accessibilityIdentifier("dashboard.launch")
            .disabled(tasks.busy && !state.networkDiagnosticRunning)
    }
    private var inspectButton: some View {
        TacticalButton(title: tasks.busy ? state.t("ui.055") : state.t("ui.049"),
                       symbol: "arrow.clockwise", primary: false, loading: tasks.busy) { state.refresh() }
            .accessibilityIdentifier("dashboard.inspect")
    }
}

private struct DashboardStatusCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: DashboardStatus.Tone
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 19)).frame(width: 24).foregroundStyle(c.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(TacticalTypography.caption).foregroundStyle(c.muted).lineLimit(2).minimumScaleFactor(0.8)
                Text(value).font(TacticalTypography.caption.weight(.semibold)).foregroundStyle(c.text).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            DashboardLED(tone: tone)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .leading)
            .background(c.panel, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(c.line, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

private struct DashboardLED: View {
    let tone: DashboardStatus.Tone
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @State private var pulse = false
    private var color: Color {
        let c = TacticalColors(scheme: scheme)
        switch tone { case .success: return c.success; case .working: return c.accent; case .failed: return c.error; case .unknown: return c.muted }
    }
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .shadow(color: color.opacity(tone == .unknown ? 0 : 0.35), radius: 3)
            .opacity(tone == .working && pulse && !reduceMotion ? 0.45 : 1)
            .animation(tone == .working && !reduceMotion ? .easeInOut(duration: 1.3).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = tone == .working && !reduceMotion }
            .onChange(of: tone) { _, value in pulse = value == .working && !reduceMotion }
            .onChange(of: reduceMotion) { _, value in pulse = tone == .working && !value }
            .accessibilityHidden(true)
    }
}
