import SwiftUI
import UniformTypeIdentifiers

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    @State private var compactOverview = false
    @State private var showingOverview = false
    @State private var locatingFX = false
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
        VStack(alignment: .leading, spacing: compactOverview ? 12 : TacticalSpacing.panel) {
            hero
            TacticalAdaptiveLayout(minimumWidth: 154, maximumColumns: 4, compactColumns: 2) {
                statusCard("FX", "shippingbox", "fx_host_running", .startingFX)
                statusCard("Steam", "play.circle", "steam_running", .startingSteam)
                statusCard("EAC", "shield.lefthalf.filled", "eac", .checkingEAC)
                statusCard(state.t("ui.191"), "person.2", "multiplayer", nil)
            }
            VStack(alignment: .leading, spacing: 12) {
                TacticalInfoRow(title: state.t("ui.graphics.mode"), value: state.t(state.graphicsChoiceKey))
                    .accessibilityIdentifier("dashboard.graphics-mode")
                if state.graphicsChoice == .dx11 || state.graphicsHasTransaction {
                    TacticalStatusBadge(text: state.t(state.graphicsStatusKey), tone: .neutral)
                }
            }
            if state.environmentWorkflow.showsDashboardLaunchControls {
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
            ViewThatFits(in: .horizontal) {
                cityBanner.frame(minWidth: 760)
                Color.clear.frame(height: 0).accessibilityHidden(true)
            }
            if let error = state.error {
                TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true)
                    .accessibilityIdentifier("bridge.error")
            }
            if state.stale { TacticalWarningBanner(text: state.t("ui.309")) }
        }
        .onGeometryChange(for: Bool.self) { $0.size.width < TacticalAdaptiveLayout.compactWidth } action: { compactOverview = $0 }
    }
    private func statusCard(_ title: String, _ symbol: String, _ key: String, _ stage: LaunchStage?) -> some View {
        let status = DashboardStatus.resolve(key: key, stage: stage, session: statusSession,
                                             workflow: statusWorkflow, evidence: statusEvidence,
                                             stale: state.stale)
        return DashboardStatusCard(title: title, value: state.t(status.textKey), symbol: symbol, tone: status.tone, compact: compactOverview)
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
            VStack(alignment: .leading, spacing: compactOverview ? 10 : 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("HELLDIVERS 2").font(TacticalTypography.brand).foregroundStyle(c.accent).lineLimit(1).minimumScaleFactor(0.75)
                        .accessibilityIdentifier("page.title").accessibilityAddTraits(.isHeader)
                    Text(state.t("ui.brand.name")).font(.system(size: 18, weight: .semibold)).foregroundStyle(c.text)
                        .lineLimit(2).minimumScaleFactor(0.75)
                }.frame(maxWidth: 380, alignment: .leading)
                HStack(spacing: 10) {
                    Text(state.t("ui.291")).font(TacticalTypography.caption.weight(.bold))
                        .foregroundStyle(c.ink).padding(.horizontal, 12).padding(.vertical, 6)
                        .background(c.yellow)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: compactOverview ? 178 : 214, alignment: .leading)
            .background { SoldierBackdrop() }
        }
        .background(c.panel).overlay(Rectangle().stroke(c.line, lineWidth: 1))
        .overlay(alignment: .top) { Rectangle().fill(c.yellow).frame(height: 3) }
    }
    private var fxControl: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack { fxHeading; Spacer(minLength: 16); fxScanActions.fixedSize(horizontal: true, vertical: false) }
                VStack(alignment: .leading, spacing: 10) {
                    fxHeading
                    ViewThatFits(in: .horizontal) {
                        fxScanActions.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: 8) { scanButton; locateButton }
                    }
                }
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
                TacticalAdaptiveLayout(minimumWidth: 285, maximumColumns: 3, fillsPartialRows: false, compactColumns: 1) {
                    ForEach(state.fxSelection.candidates, id: \.overviewCandidatePath) { candidate in
                        fxCandidate(candidate)
                    }
                }
            }
            TacticalDivider()
            Label(operationTarget, systemImage: "scope")
                .font(TacticalTypography.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .help(state.fxSelection.selectedPath ?? "")
                .accessibilityIdentifier("dashboard.fx-target")
            if state.fxSelection.candidates.count > 1, let path = state.fxSelection.selected?["path"]?.text {
                Text(path).font(TacticalTypography.caption).foregroundStyle(c.muted)
                    .lineLimit(1).truncationMode(.middle).help(path)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { fxActions }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { fxActions }
            }
            .accessibilityIdentifier("dashboard.fx-actions")
            GUIActionFeedback(state: state, methods: [GUIAction.startFX.rawValue])
        }
        .padding(TacticalSpacing.panel)
        .background { TacticalCommandFrame().fill(c.panel) }
        .overlay {
            TacticalCommandFrame().stroke(c.line, lineWidth: TacticalControlMetrics.border)
                .overlay { TacticalCommandFrame(accentsOnly: true).stroke(c.yellow, lineWidth: TacticalControlMetrics.emphasisBorder) }
                .allowsHitTesting(false).accessibilityHidden(true)
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
        HStack(spacing: 8) { scanButton; locateButton }
    }
    private var scanButton: some View {
        TacticalButton(title: state.t("ui.fx.rescan"), symbol: "arrow.clockwise", loading: scanningFX && tasks.busy,
                       disabledReason: tasks.busy ? state.t("ui.224") : nil) { scanningFX = true; state.scanFX() }
    }
    private var locateButton: some View {
        TacticalButton(title: state.t("ui.fx.locate"), symbol: "folder.badge.plus",
                       disabledReason: tasks.busy ? state.t("ui.224") : nil) { locatingFX = true }
    }
    private func fxCandidate(_ candidate: [String: JSONValue]) -> some View {
        let path = candidate["path"]?.text ?? ""
        let selected = !path.isEmpty && state.fxSelection.selectedPath == path
        let version = displayVersion(candidate)
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
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? c.accent : c.muted)
                        .accessibilityHidden(true)
                }
                HStack(spacing: 5) {
                    DashboardLED(tone: status.tone)
                    Text(state.t(status.textKey)).font(TacticalTypography.caption).foregroundStyle(c.text)
                }
                Text((path as NSString).abbreviatingWithTildeInPath).font(TacticalTypography.caption).foregroundStyle(c.muted)
                    .lineLimit(1).truncationMode(.middle).help(path)
                Text(state.t("ui.dashboard.selected")).font(TacticalTypography.caption.weight(.semibold))
                    .foregroundStyle(c.ink)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(c.yellow, in: RoundedRectangle(cornerRadius: 4))
                    .opacity(selected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .buttonStyle(FXCandidateStyle(selected: selected))
        .disabled(tasks.busy || path.isEmpty)
        .help(path)
        .accessibilityLabel((candidate["name"]?.text ?? "FX Steam Launcher") + ", " + version + ", " + state.t(status.textKey) + ", " + path)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
    @ViewBuilder private var fxActions: some View {
        TacticalButton(title: state.t("ui.316"), symbol: "play.fill",
                       loading: state.guiRecords[GUIAction.startFX.rawValue]?.status == .running,
                       disabledReason: actionDisabledReason, emphasized: true) { state.perform(.startFX) }
        TacticalButton(title: state.t("ui.323"), symbol: "stop.fill", disabledReason: state.t("ui.363")) {}
        TacticalButton(title: state.t("ui.272"), symbol: "arrow.clockwise", disabledReason: state.t("ui.363")) {}
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
    private var cityBanner: some View {
        GeometryReader { geometry in
            Image("SuperEarthCityCinematic")
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .offset(y: geometry.size.width * 0.026)
                .clipped()
                .mask {
                    LinearGradient(stops: [.init(color: .white, location: 0.88), .init(color: .white.opacity(0.7), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: TacticalControlMetrics.cardRadius))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
    private var operationTarget: String {
        guard let target = state.fxSelection.selected else { return state.t("ui.fx.choose") }
        let name = target["name"]?.text ?? "FX Steam Launcher"
        return state.t("ui.dashboard.operationTarget") + " " + name + " · " + displayVersion(target)
    }
    private func displayVersion(_ candidate: [String: JSONValue]) -> String {
        guard let version = candidate["version"]?.text, !version.isEmpty, version != "unknown" else {
            return state.t("ui.366")
        }
        return version
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

private struct FXCandidateStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var focused
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let c = TacticalColors(scheme: scheme)
        let shape = RoundedRectangle(cornerRadius: TacticalControlMetrics.cardRadius)
        let fill = if selected { enabled && configuration.isPressed ? c.pressed : enabled && hovered ? c.selectedHover : c.selected }
            else if enabled && configuration.isPressed { c.pressed }
            else if enabled && hovered { c.hover }
            else { c.elevated }
        configuration.label
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(selected || focused ? c.accent : c.line,
                                        lineWidth: focused ? TacticalControlMetrics.emphasisBorder : TacticalControlMetrics.border))
            .contentShape(shape)
            .onHover { hovered = $0 }
    }
}

private struct DashboardStatusCard: View {
    let title: String
    let value: String
    let symbol: String
    let tone: DashboardStatus.Tone
    let compact: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        let iconSize: CGFloat = compact ? 22 : 28
        HStack(spacing: 8) {
            if title == "FX" {
                Image("OverviewFXCube").renderingMode(.template).resizable().scaledToFit().frame(width: iconSize, height: iconSize)
                    .foregroundStyle(c.accent).accessibilityHidden(true)
            } else {
                Image(systemName: symbol).font(.system(size: compact ? 17 : 22)).frame(width: iconSize).foregroundStyle(c.accent).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: compact ? 2 : 5) {
                Text(title).font(TacticalTypography.caption).foregroundStyle(c.muted).lineLimit(2).minimumScaleFactor(0.8)
                Text(value).font(TacticalTypography.caption.weight(.semibold)).foregroundStyle(c.text).lineLimit(2).minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            DashboardLED(tone: tone)
        }.padding(.horizontal, 12).padding(.vertical, compact ? 6 : 12)
            .frame(maxWidth: .infinity, minHeight: compact ? 52 : 72, alignment: .leading)
            .background(c.panel, in: RoundedRectangle(cornerRadius: TacticalControlMetrics.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: TacticalControlMetrics.cardRadius)
                .strokeBorder(c.line, lineWidth: TacticalControlMetrics.border))
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
        switch tone { case .success: return c.success; case .working: return c.accent; case .failed: return c.error; case .unknown: return c.unknown }
    }
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .opacity(tone == .working && pulse && !reduceMotion ? 0.45 : 1)
            .animation(tone == .working && !reduceMotion ? .easeInOut(duration: 1.3).repeatForever(autoreverses: true) : .default, value: pulse)
            .onAppear { pulse = tone == .working && !reduceMotion }
            .onChange(of: tone) { _, value in pulse = value == .working && !reduceMotion }
            .onChange(of: reduceMotion) { _, value in pulse = tone == .working && !value }
            .accessibilityHidden(true)
    }
}
