import SwiftUI

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @Environment(\.colorScheme) private var scheme
    private var c: TacticalColors { TacticalColors(scheme: scheme) }
    private var unverified: String { state.t("未验证", "Unverified") }
    private var launchReason: String {
        state.t("启动需主动操作、指定既有运行目录，并确认实际变更；兼容性与联机仍未验证。", "Launch requires an explicit action, an existing runtime directory and approval of actual changes. Compatibility and multiplayer remain unverified.")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: TacticalSpacing.panel) {
            hero
            GUIActionFeedback(state: state, methods: [GUIAction.game.rawValue])
            if state.launchSession.current != .idle { LaunchProgressView(state: state, tasks: tasks) }
            if let error = state.error {
                TacticalWarningBanner(text: error.message(state.chinese) + " · " + error.code, isError: true)
                    .accessibilityIdentifier("bridge.error")
            }
            if state.stale {
                TacticalWarningBanner(text: state.t("以下是上次读取的数据；本次尚未完成。", "Showing the previous snapshot; this refresh has not completed."))
            }
            TacticalAdaptiveLayout(minimumWidth: 120, maximumColumns: 5) {
                TacticalMetric(title: "FX", value: observed("fx_host_running"), symbol: "shippingbox")
                TacticalMetric(title: state.t("虚拟机连接", "Guest connection"), value: observed("ssh_connected"), symbol: "link")
                TacticalMetric(title: "Steam", value: observed("steam_running"), symbol: "play.circle")
                TacticalMetric(title: "EAC", value: unverified, symbol: "shield.lefthalf.filled")
                TacticalMetric(title: state.t("联机", "Multiplayer"), value: unverified, symbol: "person.2")
            }
            TacticalStatusLayout {
                runtimeCard
                environmentCard
                report
            }
        }.foregroundStyle(c.text).font(TacticalTypography.body)
    }
    private func observed(_ key: String) -> String {
        if let value = state.latestGUIEvidence[key]?.boolean { return value ? state.t("已观察到", "Observed") : state.t("未运行／未连接", "Not running / connected") }
        if key == "steam_running", let count = state.latestGUIEvidence["steam_process_count"]?.integer { return count > 0 ? state.t("进程已观察到", "Process observed") : state.t("未发现进程", "No process found") }
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
                    TacticalStatusBadge(text: state.t("当前运行状态：未验证", "Current runtime: unverified"))
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
        TacticalButton(title: state.t("启动 HELLDIVERS 2", "Launch HELLDIVERS 2"), symbol: "play.fill", primary: true, loading: tasks.busy) { state.perform(.game) }
            .accessibilityIdentifier("dashboard.launch")
            .disabled(tasks.busy)
    }
    private var inspectButton: some View {
        TacticalButton(title: tasks.busy ? state.t("正在检查环境…", "Checking environment…") : state.t("检查环境", "Check environment"),
                       symbol: "arrow.clockwise", primary: false, loading: tasks.busy) { state.refresh() }
            .accessibilityIdentifier("dashboard.inspect")
    }
    private var runtimeCard: some View {
        TacticalPanel(number: "02", title: state.t("FX 运行时", "FX RUNTIME"), symbol: "shippingbox") {
            TacticalInfoRow(title: state.t("已发现版本", "Discovered versions"), value: versions)
            TacticalInfoRow(title: state.t("运行路径", "Runtime path"), value: state.t("未读取", "Not read"))
            Text(state.t("仅应用元数据；未识别当前运行实例。", "App metadata only; the active runtime has not been identified."))
                .font(TacticalTypography.caption).foregroundStyle(c.muted)
            if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
                Label(state.t("限定扫描不完整", "Bounded scan incomplete"), systemImage: "exclamationmark.triangle")
                    .font(TacticalTypography.caption).foregroundStyle(c.warning)
            }
        }
    }
    private var versions: String {
        guard state.hasLoaded else { return state.t("尚未读取", "Not yet inspected") }
        let values = state.rows("list_fx_versions", "candidates").map { row -> String in
            guard let version = row["version"]?.text, version != "unknown" else { return state.t("未知", "Unknown") }
            return version
        }
        return values.isEmpty ? state.t("限定范围未发现", "None in checked scope") : values.joined(separator: " / ")
    }
    private var environmentCard: some View {
        TacticalPanel(number: "03", title: state.t("运行环境", "ENVIRONMENT"), symbol: "desktopcomputer") {
            TacticalInfoRow(title: "macOS", value: state.value("get_system_info", "os_version"))
            TacticalInfoRow(title: state.t("架构", "Architecture"), value: architecture)
            TacticalInfoRow(title: "Python", value: state.value("get_system_info", "python"))
            TacticalInfoRow(title: state.t("依赖", "Dependencies"), value: dependencySummary)
        }
    }
    private var architecture: String {
        let arch = state.value("get_system_info", "arch")
        return arch == "arm64" ? "Apple Silicon / arm64" : arch
    }
    private var dependencySummary: String {
        let rows = state.rows("get_dependencies", "items")
        guard !rows.isEmpty else { return state.t("尚未读取", "Not yet inspected") }
        if rows.contains(where: { ["missing", "invalid"].contains($0["state"]?.text ?? "") }) {
            return state.t("本地文件需检查", "Local files need review")
        }
        return unverified
    }
    private var networkCard: some View {
        TacticalPanel(number: "04", title: state.t("网络", "NETWORK"), symbol: "network") {
            TacticalStatusBadge(text: unverified)
            TacticalInfoRow(title: "SSH", value: unverified)
            TacticalInfoRow(title: "Guest", value: unverified)
            TacticalInfoRow(title: state.t("联机", "Multiplayer"), value: unverified)
            Text(state.t("本阶段未发起连接或网络探测。", "No connections or network probes in this phase."))
                .font(TacticalTypography.caption).foregroundStyle(c.muted)
        }
    }
    private var refreshTime: String {
        guard let raw = state.observedAt else { return state.t("尚未刷新", "Not refreshed") }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = parser.date(from: raw) else { return raw }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: state.chinese ? "zh_CN" : "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
    private var report: some View {
        TacticalPanel(number: "04", title: state.t("系统报告", "SYSTEM REPORT"), symbol: "doc.text") {
            TacticalInfoRow(title: state.t("启动器版本", "Launcher version"), value: state.value("get_launcher_version", "version"))
            TacticalInfoRow(title: state.t("最近刷新 · 北京时间", "Last refresh · UTC+08"), value: refreshTime)
            TacticalInfoRow(title: state.t("检测范围", "Inspection scope"), value: state.t("本机元数据 / 依赖文件 / 限定 FX 目录", "Host metadata / dependency files / bounded FX directories"))
            TacticalInfoRow(title: state.t("最近 Bridge 错误", "Latest Bridge error"), value: state.error.map { $0.code } ?? state.t("本次无错误记录", "No error recorded in this refresh"))
            TacticalNavigationItem(number: "04", title: state.t("打开本次会话日志", "Open session logs"), symbol: "doc.text", shortcut: "↗") { state.selection = .logs }
                .accessibilityIdentifier("dashboard.logs")
        }
    }
}
