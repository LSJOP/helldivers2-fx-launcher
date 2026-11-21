import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    @State private var showingOverview = false
    @State private var locatingFX = false
    @State private var showingFXDetails = false
    @State private var scanningFX = false
    private var c: TacticalColors { TacticalColors(scheme: scheme) }
    var body: some View {
        Group {
            if state.selection != .fx && state.environmentWorkflow.launchesGame && state.environmentWorkflow.phase != .idle && !showingOverview {
                launchPreparation
            } else {
                overview
            }
        }
        .foregroundStyle(c.text).font(TacticalTypography.body)
        .fileImporter(isPresented: $locatingFX, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result { state.scanFX(manualPath: url.path) }
        }
        .sheet(isPresented: $showingFXDetails) {
            VStack(alignment: .trailing, spacing: 0) {
                TacticalButton(title: state.t("ui.037"), symbol: "xmark") { showingFXDetails = false }
                    .padding([.top, .trailing])
                ScrollView { FXManagerView(state: state).padding(TacticalSpacing.page) }
            }
            .frame(minWidth: 680, minHeight: 560)
        }
        .onChange(of: state.environmentWorkflow.taskID) { _, _ in
            if state.environmentWorkflow.launchesGame { showingOverview = false }
        }
        .onChange(of: tasks.busy) { _, busy in
            if !busy { scanningFX = false }
        }
    }
    private var launchPreparation: some View {
        VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
            TacticalPageHeader(title: state.t("ui.176"))
            TacticalFlowArtwork(asset: "MOTR7Soldier") {
                VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
                    TacticalFlowMark()
                    EnvironmentWorkflowProgressView(state: state, tasks: tasks, showStepsInline: true, returnToDashboard: { showingOverview = true })
                    TacticalButton(title: state.t("ui.092"), symbol: "square.grid.2x2", primary: false) { showingOverview = true }
                    TacticalFlowFooter()
                }
            }
            if let error = state.error { TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true) }
            if state.stale { TacticalWarningBanner(text: state.t("ui.309")) }
        }
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
            hero
            TacticalAdaptiveLayout(minimumWidth: 170, maximumColumns: 4) {
                statusCard("FX", "shippingbox", "fx_host_running", .startingFX)
                statusCard("Steam", "play.circle", "steam_running", .startingSteam)
                statusCard("EAC", "shield.lefthalf.filled", "eac", .checkingEAC)
                statusCard(state.t("ui.191"), "person.2", "multiplayer", nil)
            }
            if state.environmentWorkflow.phase == .idle {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) { launchButton.frame(maxWidth: 570); inspectButton; Spacer(minLength: 0) }
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
            fxControl
            horizon
            if let error = state.error {
                TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true)
                    .accessibilityIdentifier("bridge.error")
            }
            if state.stale { TacticalWarningBanner(text: state.t("ui.309")) }
        }
    }
    private func statusCard(_ title: String, _ symbol: String, _ key: String, _ stage: LaunchStage?) -> some View {
        let status = DashboardStatus.resolve(key: key, stage: stage, session: statusSession,
                                             workflow: statusWorkflow, evidence: statusEvidence,
                                             stale: state.stale)
        return DashboardStatusCard(title: title, value: state.t(status.textKey), symbol: symbol, tone: status.tone,
                                   unverified: key == "eac" || key == "multiplayer")
    }
    private var statusInputs: (LaunchSession, EnvironmentWorkflow, [String: JSONValue]) {
        DashboardStatus.boundInputs(root: state.runtimeRoot, session: state.launchSession,
                                    workflow: state.environmentWorkflow, evidence: state.latestGUIEvidence)
    }
    private var statusSession: LaunchSession { statusInputs.0 }
    private var statusWorkflow: EnvironmentWorkflow { statusInputs.1 }
    private var statusEvidence: [String: JSONValue] { statusInputs.2 }

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
                    Text(state.t("ui.291")).font(TacticalTypography.caption.weight(.bold))
                        .foregroundStyle(c.ink).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(c.yellow)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 260, alignment: .leading)
            .background { SoldierBackdrop() }
        }
        .background(c.panel).overlay(Rectangle().stroke(c.line, lineWidth: 1))
        .overlay(alignment: .top) { Rectangle().fill(c.yellow).frame(height: 3) }
    }
    private var fxControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { fxHeading; Spacer(); fxScanActions }
                VStack(alignment: .leading, spacing: 10) { fxHeading; fxScanActions }
            }
            TacticalDivider()
            if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
                TacticalWarningBanner(text: scanWarning + " " + state.t("ui.357"))
            }
            if state.fxSelectionIssue { TacticalWarningBanner(text: state.t("ui.fx.invalid")) }
            if state.fxSelection.candidates.isEmpty {
                Text(state.fxSelection.scanned ? state.fxStatus : state.t("ui.089"))
                    .font(TacticalTypography.body).foregroundStyle(c.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
            } else {
                TacticalAdaptiveLayout(minimumWidth: 230, maximumColumns: 3) {
                    ForEach(state.fxSelection.candidates, id: \.overviewCandidatePath) { candidate in
                        fxCandidate(candidate)
                    }
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { fxActions }.fixedSize(horizontal: true, vertical: false)
                TacticalAdaptiveLayout(minimumWidth: 145, maximumColumns: 3) { fxActions }
            }
            GUIActionFeedback(state: state, methods: [GUIAction.startFX.rawValue, GUIAction.steam.rawValue])
        }
        .padding(TacticalSpacing.panel)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 6).fill(c.panel)
                if scheme == .dark {
                    Image("OverviewFXPanelFrame")
                        .resizable(capInsets: EdgeInsets(top: 22, leading: 24, bottom: 22, trailing: 24), resizingMode: .stretch)
                } else {
                    RoundedRectangle(cornerRadius: 6).stroke(c.accent, lineWidth: 1.5)
                }
            }.allowsHitTesting(false).accessibilityHidden(true)
        }
        .accessibilityIdentifier("dashboard.fx-control")
    }
    private var fxHeading: some View {
        HStack(spacing: 10) {
            Image("OverviewFXCube").renderingMode(.template).resizable().scaledToFit().frame(width: 30, height: 30)
                .foregroundStyle(c.accent).accessibilityHidden(true)
            Text(state.t("ui.dashboard.fxControl")).font(TacticalTypography.value.weight(.bold))
        }
    }
    private var fxScanActions: some View {
        HStack(spacing: 8) {
            TacticalButton(title: state.t("ui.fx.rescan"), symbol: "arrow.clockwise", loading: scanningFX && tasks.busy,
                           disabledReason: tasks.busy ? state.t("ui.224") : nil) { scanningFX = true; state.scanFX() }
            TacticalButton(title: state.t("ui.fx.locate"), symbol: "folder.badge.plus",
                           disabledReason: tasks.busy ? state.t("ui.224") : nil) { locatingFX = true }
        }
    }
    private func fxCandidate(_ candidate: [String: JSONValue]) -> some View {
        let path = candidate["path"]?.text ?? ""
        let selected = !path.isEmpty && state.fxSelection.selectedPath == path
        let version = candidate["version"]?.text.flatMap { $0 == "unknown" || $0.isEmpty ? nil : $0 } ?? state.t("ui.366")
        let status = selected ? DashboardStatus.resolve(key: "fx_host_running", stage: .startingFX, session: statusSession,
                                                        workflow: statusWorkflow, evidence: statusEvidence,
                                                        stale: state.stale) : DashboardStatus(tone: .unknown, textKey: "ui.368")
        return Button {
            guard !path.isEmpty else { return }
            state.selectFX(path)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image("OverviewFXCube").renderingMode(.template).resizable().scaledToFit().frame(width: 23, height: 23)
                        .foregroundStyle(c.accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate["name"]?.text ?? "FX Steam Launcher").font(TacticalTypography.body.weight(.bold)).lineLimit(2)
                        Text(version).font(TacticalTypography.caption).foregroundStyle(c.muted)
                    }
                    Spacer(minLength: 15)
                }
                HStack(spacing: 5) {
                    DashboardLED(tone: status.tone)
                    Text(state.t(status.textKey)).font(TacticalTypography.caption).foregroundStyle(c.text)
                    if selected { Text("· " + state.t("ui.dashboard.selected")).font(TacticalTypography.caption).foregroundStyle(c.accent) }
                }
                Text((path as NSString).abbreviatingWithTildeInPath).font(TacticalTypography.caption).foregroundStyle(c.muted)
                    .lineLimit(1).truncationMode(.middle).help(path)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background {
                ZStack(alignment: .trailing) {
                    RoundedRectangle(cornerRadius: 5).fill(c.secondary)
                    if scheme == .dark {
                        Image(selected ? "OverviewFXSelectedFrame" : "OverviewFXIdleFrame")
                            .resizable(capInsets: EdgeInsets(top: 28, leading: 15, bottom: 15, trailing: 28), resizingMode: .stretch)
                    } else {
                        RoundedRectangle(cornerRadius: 5).stroke(selected ? c.accent : c.line, lineWidth: selected ? 2 : 1)
                    }
                    Image("OverviewFXWatermark").resizable().scaledToFit().frame(width: 90).opacity(0.1).accessibilityHidden(true)
                }
            }
            .overlay(alignment: .topTrailing) {
                if selected && scheme == .light {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(c.accent).padding(8).accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(tasks.busy || path.isEmpty)
        .help(path)
        .accessibilityLabel((candidate["name"]?.text ?? "FX Steam Launcher") + ", " + version + ", " + state.t(status.textKey) + ", " + path)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private var fxActions: some View {
        TacticalButton(title: state.t("ui.316"), symbol: "play.fill", primary: true,
                       loading: state.guiRecords[GUIAction.startFX.rawValue]?.status == .running,
                       disabledReason: actionDisabledReason, fillsWidth: true) { state.perform(.startFX) }
        TacticalButton(title: state.t("ui.323"), symbol: "stop.fill", disabledReason: state.t("ui.363"), fillsWidth: true) {}
        TacticalButton(title: state.t("ui.272"), symbol: "arrow.clockwise", disabledReason: state.t("ui.363"), fillsWidth: true) {}
        TacticalButton(title: state.t("ui.317"), symbol: "play.circle", loading: state.guiRecords[GUIAction.steam.rawValue]?.status == .running,
                       disabledReason: actionDisabledReason, fillsWidth: true) { state.perform(.steam) }
        TacticalButton(title: state.t("ui.dashboard.more"), symbol: "ellipsis", fillsWidth: true) { showingFXDetails = true }
    }
    private var actionDisabledReason: String? {
        if tasks.busy { return state.t("ui.224") }
        if state.fxSelection.selected == nil { return state.t("ui.fx.choose") }
        return nil
    }
    private var scanWarning: String {
        let issues = state.results["list_fx_versions"]?["issues"]?.array.compactMap(\.text) ?? []
        return state.t(issues.contains("DIRECTORY_UNAVAILABLE") ? "ui.227" : "ui.228")
    }
    private var horizon: some View {
        GeometryReader { geometry in
            Image("OverviewHorizon").resizable().aspectRatio(contentMode: .fill)
                .frame(width: geometry.size.width, height: 150, alignment: .bottom).clipped()
                .opacity(scheme == .dark ? 0.65 : 0.55)
        }
        .frame(height: 150).accessibilityHidden(true).allowsHitTesting(false)
    }
    private var launchButton: some View {
        TacticalButton(title: state.t("ui.176"), symbol: "play.fill", primary: true, loading: tasks.busy && !state.networkDiagnosticRunning, fillsWidth: true) { showingOverview = false; state.perform(.game) }
            .accessibilityIdentifier("dashboard.launch")
            .disabled(tasks.busy && !state.networkDiagnosticRunning)
    }
    private var inspectButton: some View {
        TacticalButton(title: tasks.busy ? state.t("ui.055") : state.t("ui.049"),
                       symbol: "arrow.clockwise", primary: false, loading: tasks.busy) { state.refresh() }
            .accessibilityIdentifier("dashboard.inspect")
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var overviewCandidatePath: String { self["path"]?.text ?? "" }
}

private struct DashboardStatusCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: DashboardStatus.Tone
    let unverified: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(spacing: 8) {
            if title == "FX" {
                Image("OverviewFXCube").renderingMode(.template).resizable().scaledToFit().frame(width: 28, height: 28)
                    .foregroundStyle(c.accent).accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.system(size: 22)).frame(width: 28).foregroundStyle(c.accent).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(TacticalTypography.caption).foregroundStyle(c.muted).lineLimit(2).minimumScaleFactor(0.8)
                Text(value).font(TacticalTypography.caption.weight(.semibold)).foregroundStyle(c.text).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if tone == .success || (tone == .unknown && unverified) || tone == .unknown {
                Image(tone == .success ? "OverviewStatusCheck" : unverified ? "OverviewStatusWarning" : "OverviewStatusUnknown")
                    .resizable().scaledToFit().frame(width: 16, height: 16).accessibilityHidden(true)
            } else {
                DashboardLED(tone: tone)
            }
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
