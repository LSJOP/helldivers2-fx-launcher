import SwiftUI

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    private var c: TacticalColors { TacticalColors(scheme: scheme) }
    private var unverified: String { state.t("ui.368") }
    private var launchReason: String {
        state.t("ui.180")
    }
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
            EnvironmentWorkflowProgressView(state: state, tasks: tasks)
            if state.environmentWorkflow.phase == .idle {
                GUIActionFeedback(state: state, methods: [GUIAction.game.rawValue])
                if state.launchSession.current != .idle { LaunchProgressView(state: state, tasks: tasks) }
            }
            if let error = state.error {
                TacticalWarningBanner(text: error.message(state.languageCode) + " · " + error.code, isError: true)
                    .accessibilityIdentifier("bridge.error")
            }
            if state.stale {
                TacticalWarningBanner(text: state.t("ui.309"))
            }
            TacticalStatusLayout {
                runtimeCard
                environmentCard
                report
            }
        }.foregroundStyle(c.text).font(TacticalTypography.body)
    }
    private func observed(_ key: String) -> String {
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
                    Text("FX LAUNCHER").font(.system(size: 19, weight: .bold, design: .monospaced)).tracking(4).foregroundStyle(c.text)
                }.frame(maxWidth: 380, alignment: .leading)
                HStack(spacing: 10) {
                    TacticalStatusBadge(text: state.t("ui.089"))
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .leading)
            .background { SoldierBackdrop() }
            TacticalDivider()
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { launchButton; inspectButton }
                    VStack(alignment: .leading, spacing: 10) { launchButton; inspectButton }
                }
                TacticalWarningBanner(text: launchReason)
            }.padding(16)
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
    private var runtimeCard: some View {
        TacticalPanel(number: "02", title: state.t("ui.118"), symbol: "shippingbox") {
            TacticalInfoRow(title: state.t("ui.fx.installState"),
                            value: state.fxSelection.selected == nil ? state.t("ui.fx.statusNotDetected") : state.t("ui.fx.statusDetected"))
            TacticalInfoRow(title: state.t("ui.fx.runState"), value: runStateText)
            TacticalInfoRow(title: state.t("ui.fx.resourceCheck"), value: resourceCheckText)
            Text(state.t("ui.fx.actionHint"))
                .font(TacticalTypography.caption).foregroundStyle(c.muted)
            if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
                Label(state.t("ui.034"), systemImage: "exclamationmark.triangle")
                    .font(TacticalTypography.caption).foregroundStyle(c.warning)
            }
        }
    }
    private var runStateText: String {
        let recent = state.guiRecords.values.filter { ["start_fx", "launch_game", "check_fx_state", "connect_fx"].contains($0.method) }
            .max { $0.startedAt < $1.startedAt }
        if let recent, recent.status == .running { return state.t("ui.fx.statusStarting") }
        if let recent, recent.status == .failed { return state.t("ui.fx.statusFailed") }
        switch state.latestGUIEvidence["fx_host_running"]?.boolean {
        case .some(true): return state.t("ui.fx.statusRunning")
        case .some(false): return state.t("ui.fx.statusNotRunning")
        case .none: return state.t("ui.fx.statusUnknown")
        }
    }
    private var resourceCheckText: String {
        if state.targetInspection["archive_files_match"]?.boolean == true { return state.t("ui.190") }
        if let error = state.targetInspectionError { return error.code }
        if !state.targetInspection.isEmpty { return state.t("ui.fx.statusFailed") }
        return state.t("ui.208")
    }
    private var versions: String {
        guard state.hasLoaded else { return state.t("ui.217") }
        let values = state.rows("list_fx_versions", "candidates").map { row -> String in
            guard let version = row["version"]?.text, version != "unknown" else { return state.t("ui.366") }
            return version
        }
        return values.isEmpty ? state.t("ui.205") : values.joined(separator: " / ")
    }
    private var environmentCard: some View {
        TacticalPanel(number: "03", title: state.t("ui.104"), symbol: "desktopcomputer") {
            TacticalInfoRow(title: "macOS", value: state.value("get_system_info", "os_version"))
            TacticalInfoRow(title: state.t("ui.026"), value: architecture)
            TacticalInfoRow(title: state.t("ui.native.runtime"), value: state.value("get_system_info", "native_runtime"))
            TacticalInfoRow(title: state.t("ui.093"), value: dependencySummary)
        }
    }
    private var architecture: String {
        let arch = state.value("get_system_info", "arch")
        return arch == "arm64" ? "Apple Silicon / arm64" : arch
    }
    private var dependencySummary: String {
        let rows = state.rows("get_dependencies", "items")
        guard !rows.isEmpty else { return state.t("ui.217") }
        if rows.contains(where: { ["missing", "invalid"].contains($0["state"]?.text ?? "") }) {
            return state.t("ui.186")
        }
        return unverified
    }
    private var networkCard: some View {
        TacticalPanel(number: "04", title: state.t("ui.192"), symbol: "network") {
            TacticalStatusBadge(text: unverified)
            TacticalInfoRow(title: "SSH", value: unverified)
            TacticalInfoRow(title: "Guest", value: unverified)
            TacticalInfoRow(title: state.t("ui.191"), value: unverified)
            Text(state.t("ui.196"))
                .font(TacticalTypography.caption).foregroundStyle(c.muted)
        }
    }
    private var refreshTime: String {
        guard let raw = state.observedAt else { return state.t("ui.213") }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: state.languageCode)
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    private var report: some View {
        TacticalPanel(number: "04", title: state.t("ui.292"), symbol: "doc.text") {
            TacticalInfoRow(title: state.t("ui.181"), value: state.value("get_launcher_version", "version"))
            TacticalInfoRow(title: state.t("ui.173"), value: refreshTime)
            TacticalInfoRow(title: state.t("ui.164"), value: state.t("ui.151"))
            TacticalInfoRow(title: state.t("ui.174"), value: state.error.map { $0.code } ?? state.t("ui.198"))
            TacticalNavigationItem(number: "04", title: state.t("ui.221"), symbol: "doc.text", shortcut: "↗") { state.selection = .logs }
                .accessibilityIdentifier("dashboard.logs")
        }
    }
}
