import SwiftUI

struct TacticalDivider: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View { Rectangle().fill(TacticalColors(scheme: scheme).line).frame(height: 1) }
}

struct TacticalSectionHeader: View {
    let number: String
    let title: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(spacing: TacticalSpacing.small) {
            Text(number).foregroundStyle(c.accent)
            Image(systemName: symbol).foregroundStyle(c.muted).accessibilityHidden(true)
            Text(title).foregroundStyle(c.text)
        }.font(TacticalTypography.module).accessibilityElement(children: .combine)
    }
}

struct TacticalPanel<Content: View>: View {
    let number: String
    let title: String
    let symbol: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        VStack(alignment: .leading, spacing: TacticalSpacing.medium) {
            TacticalSectionHeader(number: number, title: title, symbol: symbol)
            TacticalDivider()
            content
        }
        .padding(TacticalSpacing.panel).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(c.panel, in: RoundedRectangle(cornerRadius: TacticalSpacing.corner))
        .overlay(RoundedRectangle(cornerRadius: TacticalSpacing.corner).stroke(c.line, lineWidth: 1))
        .overlay(alignment: .topLeading) { Rectangle().fill(c.accent).frame(width: 24, height: 2) }
    }
}

enum TacticalTone { case neutral, checking, warning, error, success }

struct TacticalStatusBadge: View {
    let text: String
    var tone: TacticalTone = .neutral
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        let color = tone == .error ? c.error : tone == .warning ? c.warning : tone == .checking ? c.accent : tone == .success ? c.success : c.muted
        Label(text, systemImage: tone == .neutral ? "circle.dashed" : tone == .error ? "exclamationmark.circle" : tone == .success ? "checkmark.circle" : "clock")
            .font(TacticalTypography.caption).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color.opacity(0.08)).overlay(Rectangle().stroke(color.opacity(0.5), lineWidth: 1))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct TacticalInfoRow: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).foregroundStyle(c.muted).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 6)
                Text(value).foregroundStyle(c.text).multilineTextAlignment(.trailing).fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).foregroundStyle(c.muted)
                Text(value).foregroundStyle(c.text)
            }
        }.font(TacticalTypography.body).frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            .accessibilityElement(children: .combine)
    }
}

struct TacticalWarningBanner: View {
    let text: String
    var isError = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        Label(text, systemImage: isError ? "exclamationmark.triangle" : "lock.shield")
            .font(TacticalTypography.caption).foregroundStyle(isError ? c.error : c.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background((isError ? c.error : c.accent).opacity(0.06))
            .overlay(alignment: .leading) { Rectangle().fill(isError ? c.error : c.accent).frame(width: 2) }
    }
}

struct TacticalButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        let c = TacticalColors(scheme: scheme)
        let filled = enabled && (primary || configuration.isPressed)
        configuration.label.font(TacticalTypography.body.weight(.semibold))
            .foregroundColor(filled ? c.ink : enabled ? c.text : c.muted)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(filled ? c.yellow : hovered && enabled ? c.line.opacity(0.35) : c.secondary)
            .overlay(Rectangle().stroke(focused ? c.accent : primary ? c.accent.opacity(enabled ? 1 : 0.5) : c.line, lineWidth: focused ? 2 : 1))
            .drawingGroup()
            .contentShape(Rectangle()).onHover { hovered = $0 }
    }
}

struct TacticalButton: View {
    let title: String
    let symbol: String
    var primary = false
    var loading = false
    var disabledReason: String? = nil
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().controlSize(.mini) }
                else { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title)
            }
        }
        .buttonStyle(TacticalButtonStyle(primary: primary))
        .disabled(loading || disabledReason != nil)
        .help(disabledReason ?? title)
        .accessibilityLabel(title).accessibilityHint(disabledReason ?? "")
    }
}

struct TacticalNavigationItem: View {
    let number: String
    let title: String
    let symbol: String
    var selected = false
    var shortcut: String = ""
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var focused
    @State private var hovered = false
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        Button(action: action) {
            HStack(spacing: 8) {
                Text(number).font(TacticalTypography.log).frame(width: 22, alignment: .leading)
                Image(systemName: symbol).frame(width: 16).accessibilityHidden(true)
                Text(title).font(TacticalTypography.body.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(shortcut).font(TacticalTypography.log).frame(width: 22, alignment: .trailing)
            }
            .foregroundColor(selected ? c.ink : c.text)
            .padding(.horizontal, 10).padding(.vertical, 10)
            .background(selected ? c.yellow : hovered ? c.line.opacity(0.25) : c.secondary)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(c.ink).frame(width: 3).padding(.vertical, 9) } }
            .overlay(Rectangle().stroke(focused ? c.accent : .clear, lineWidth: 2))
            .drawingGroup()
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// One shared secondary-page banner. Artwork is bundled, decorative and noninteractive.
struct TacticalPageHeader: View {
    let title: String
    var refreshState: AppState? = nil
    private let height: CGFloat = 160
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Color(red: 0.035, green: 0.043, blue: 0.055)
                Image("SuperEarthSpaceHeader")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    // Fit the entire vertical composition, including all stars and wings.
                    // On narrow windows only spare scenery at the left may leave the bounds.
                    .frame(width: height * 3, height: height)
                    .mask(LinearGradient(stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white, location: 0.45),
                        .init(color: .white, location: 1)
                    ], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width - 8, height: height, alignment: .trailing)
                    .accessibilityHidden(true).allowsHitTesting(false)
                VStack(alignment: .leading, spacing: 12) {
                    Rectangle().fill(TacticalColors(scheme: .dark).yellow).frame(width: 28, height: 2)
                    HStack(alignment: .center, spacing: 12) {
                        Text(title).font(TacticalTypography.page).foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("page.title").accessibilityAddTraits(.isHeader)
                        if let refreshState {
                            TacticalRefreshButton(state: refreshState, tasks: refreshState.tasks)
                                .fixedSize()
                        }
                    }
                }
                // Reserve the right-hand emblem region so neither title nor button covers it.
                .frame(width: max(1, geometry.size.width - 230), alignment: .leading)
                .padding(.leading, 20)
            }
            .clipped()
            .overlay(alignment: .bottom) {
                Rectangle().fill(TacticalColors(scheme: .dark).yellow).frame(height: 1)
            }
        }
        .frame(height: height)
    }
}

struct TacticalMetric: View {
    let title: String
    let value: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 21)).foregroundStyle(c.accent).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(TacticalTypography.caption).foregroundStyle(c.muted)
                Text(value).font(TacticalTypography.body.weight(.semibold)).foregroundStyle(c.text)
            }
        }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(c.panel, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(c.line, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
}

// Presentation of existing evidence only. File presence never becomes runtime health.
@MainActor enum TacticalEvidence {
    static func dependency(_ value: String, _ state: AppState) -> String {
        switch value {
        case "running_bridge": return state.t("本次解释器使用中", "Interpreter in use")
        case "file_present_unverified": return state.t("文件已发现 · 未验证", "File found · Unverified")
        case "missing": return state.t("限定路径未找到", "Not found in checked paths")
        case "invalid": return state.t("文件不可执行", "File is not executable")
        default: return state.t("未验证", "Unverified")
        }
    }
    static func name(_ name: String, _ state: AppState) -> String {
        switch name {
        case "Game components": return state.t("游戏组件", "Game components")
        case "FX runtime": return state.t("FX 运行时", "FX runtime")
        case "gvproxy runtime": return state.t("gvproxy 运行时", "gvproxy runtime")
        case "SSH connection": return state.t("SSH 连接", "SSH connection")
        case "Multiplayer": return state.t("联机", "Multiplayer")
        default: return name
        }
    }
}

/// Keeps complete rows across the proposed width; never reserves empty grid slots.
struct TacticalAdaptiveLayout: Layout {
    var minimumWidth: CGFloat
    var maximumColumns: Int
    private let gap: CGFloat = 12
    private func columns(_ width: CGFloat, count: Int) -> Int {
        let n = min(count, maximumColumns, max(1, Int((width + gap) / (minimumWidth + gap))))
        if count == 4 && n == 3 { return 2 }
        if count == 5 && n == 4 { return 3 }
        if count == 6 && n > 3 && n < 6 { return 3 }
        return max(1, n)
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 700
        let cols = columns(width, count: subviews.count)
        var height: CGFloat = 0
        for start in stride(from: 0, to: subviews.count, by: cols) {
            let row = start..<min(start+cols, subviews.count)
            let w = (width - gap * CGFloat(row.count-1)) / CGFloat(row.count)
            let h = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
            height += h + (start == 0 ? 0 : gap)
        }
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let cols = columns(bounds.width, count: subviews.count)
        var y = bounds.minY
        for start in stride(from: 0, to: subviews.count, by: cols) {
            let row = start..<min(start+cols, subviews.count)
            let w = (bounds.width-gap*CGFloat(row.count-1))/CGFloat(row.count)
            let h = row.map { subviews[$0].sizeThatFits(ProposedViewSize(width: w, height: nil)).height }.max() ?? 0
            for i in row {
                subviews[i].place(at: CGPoint(x: bounds.minX+CGFloat(i-start)*(w+gap), y: y), anchor: .topLeading, proposal: ProposedViewSize(width: w, height: h))
            }
            y += h+gap
        }
    }
}

// Every page refresh uses the same read-only snapshot transaction as Dashboard / Cmd-R.
struct TacticalRefreshButton: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    var body: some View {
        Button { state.refresh() } label: {
            HStack(spacing: 6) {
                if state.refreshing { ProgressView().controlSize(.mini) }
                else { Image(systemName: "arrow.clockwise") }
                Text(state.t("刷新", "Refresh"))
            }.font(TacticalTypography.caption).padding(.horizontal, 9).padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(white: 0.92))
        .background(Color(white: 0.14))
        .overlay(Rectangle().stroke(Color(white: 0.38), lineWidth: 1))
        .opacity(tasks.busy ? 0.55 : 1)
        .disabled(tasks.busy)
        .help(state.t("刷新全部只读快照：本机环境、依赖、FX 安装、会话日志及功能清单；不会启动或修改运行环境。也可按 ⌘R。", "Refresh all read-only snapshots: host environment, dependencies, FX installations, session logs and capabilities. No runtime starts or changes. Also available with ⌘R."))
        .accessibilityIdentifier("refresh")
    }
}

// Presentation of the bounded snapshot only; missing runtime probes never become health.
enum InspectionStatus {
    case unchecked, checking, normal, action, failed, uncertain
    var tone: TacticalTone {
        switch self {
        case .unchecked, .uncertain: return .neutral
        case .checking: return .checking
        case .normal: return .success
        case .action: return .warning
        case .failed: return .error
        }
    }
    @MainActor func title(_ state: AppState) -> String {
        switch self {
        case .unchecked: return state.t("未检查", "Not checked")
        case .checking: return state.t("检查中", "Checking")
        case .normal: return state.t("正常", "Normal")
        case .action: return state.t("需要操作", "Action needed")
        case .failed: return state.t("检查失败", "Check failed")
        case .uncertain: return state.t("无法确认", "Cannot confirm")
        }
    }
    static func dependency(_ raw: String?) -> Self {
        switch raw {
        case nil: return .unchecked
        case "running_bridge": return .normal
        case "missing", "invalid": return .action
        default: return .uncertain
        }
    }
}


struct GUIOperationsPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    var environment = true
    private var methods: [GUIAction] { environment ? [.connect, .inspect] : [.startFX, .fxState, .connect, .steam, .game] }
    private var last: GUIOperationRecord? {
        state.guiRecords.values.filter { $0.target == state.runtimeRoot && methods.map(\.rawValue).contains($0.method) }.max { $0.startedAt < $1.startedAt }
    }
    private var inspection: [String: JSONValue] { state.guiSnapshots[GUIAction.inspect.rawValue] ?? [:] }
    private var connection: [String: JSONValue] {
        [GUIAction.connect, .inspect, .steam].compactMap { action -> (Date, [String: JSONValue])? in
            guard let row = state.guiRecords[action.rawValue], row.target == state.runtimeRoot,
                  let data = state.guiSnapshots[action.rawValue] else { return nil }
            return (row.endedAt ?? row.startedAt, data)
        }.max { $0.0 < $1.0 }?.1 ?? [:]
    }
    var body: some View {
        TacticalPanel(number: "↗", title: state.t(environment ? "FX 连接与环境" : "FX 操作", environment ? "FX connection and environment" : "FX actions"), symbol: "point.3.connected.trianglepath.dotted") {
            TacticalInfoRow(title: state.t("当前目标", "Selected target"), value: state.runtimeRoot.isEmpty ? state.t("尚未选择；点击操作后选择已有启动目录", "Not selected; choose the existing launcher directory when opening an action") : state.runtimeRoot)
            TacticalAdaptiveLayout(minimumWidth: 170, maximumColumns: 3) {
                ForEach(methods) { action in
                    TacticalButton(title: state.t(action.labels.0, action.labels.1), symbol: symbol(action), primary: action == .connect || action == .startFX,
                                   loading: state.guiRecords[action.rawValue]?.status == .running,
                                   disabledReason: tasks.busy ? state.t("已有操作执行中，请等待或取消当前操作", "An operation is running; wait or cancel it") : nil) { state.perform(action) }
                }
                if environment {
                    TacticalButton(title: state.t("重新检测", "Inspect again"), symbol: "arrow.clockwise", disabledReason: tasks.busy ? state.t("操作执行中", "Operation in progress") : nil) { state.perform(.inspect) }
                } else {
                    TacticalButton(title: state.t("停止 FX", "Stop FX"), symbol: "stop.fill", disabledReason: state.t("暂不可用：尚无经验证的正常退出接口，请在 FX 中正常退出", "Unavailable: no verified graceful-quit backend; quit normally in FX")) {}
                    TacticalButton(title: state.t("重启 FX", "Restart FX"), symbol: "restart", disabledReason: state.t("暂不可用：需先接入安全退出与重启验证", "Unavailable: requires a verified safe stop/restart workflow")) {}
                }
            }
            if !environment {
                Text(state.t("停止／重启暂不可用：尚未接入可验证的安全退出流程。", "Stop/restart unavailable: a verified graceful-exit workflow is not integrated."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            if connection["ssh_connected"]?.boolean == true {
                TacticalStatusBadge(text: state.t("已连接 · 最近检查", "Connected · Last check"), tone: .success)
            } else { TacticalStatusBadge(text: state.t("连接尚未验证", "Connection not verified")) }
            if let record = last {
                TacticalInfoRow(title: state.t("操作", "Action"), value: title(record.method))
                TacticalStatusBadge(text: status(record.status), tone: tone(record.status))
                TacticalInfoRow(title: state.t("开始时间", "Started"), value: record.startedAt.formatted(date: .omitted, time: .standard))
                if let end = record.endedAt { TacticalInfoRow(title: state.t("结束时间", "Finished"), value: end.formatted(date: .omitted, time: .standard)) }
                if let error = record.error {
                    TacticalWarningBanner(text: error.message(state.chinese), isError: true)
                    Button(state.t("查看详情／处理", "Details / Resolve")) { state.operationSelection = NativeOperation(method: record.method) }
                } else if record.status == .succeeded { Text(summary(record.method)).font(TacticalTypography.body) }
                if record.status == .running { Button(state.t("取消当前操作", "Cancel current operation")) { tasks.cancel() } }
            } else { TacticalStatusBadge(text: state.t("未开始", "Not started")) }
            if !inspection.isEmpty {
                TacticalDivider()
                TacticalInfoRow(title: state.t("Guest 系统", "Guest system"), value: inspection["guest_os"]?.text ?? "—")
                TacticalInfoRow(title: state.t("Guest 架构", "Guest architecture"), value: inspection["guest_arch"]?.text ?? "—")
                let components = inspection["components"]?.object ?? [:]
                ForEach(["steam_files","game_manifest","game_directory","game_executable","proton_files","fex_files"], id: \.self) { name in
                    TacticalInfoRow(title: component(name), value: components[name]?.boolean == true ? state.t("已发现 · 文件证据", "Found · File evidence") : state.t("限定位置未发现", "Not found in checked locations"))
                }
                TacticalInfoRow(title: state.t("Steam 进程 · 上次检测", "Steam processes · Last inspection"), value: String(inspection["steam_process_count"]?.integer ?? 0))
                TacticalInfoRow(title: state.t("游戏进程 · 上次检测", "Game processes · Last inspection"), value: String(inspection["game_process_count"]?.integer ?? 0))
            }
            Text(state.t("显示最近一次检查结果，并非常驻连接监控。文件存在不代表可运行；游戏进程不代表进入主菜单。检查操作不修改 Guest，启动和变更需另行确认。", "Results describe the last check, not continuous monitoring. File presence does not establish readiness; a process does not prove the game menu. Inspection does not change Guest configuration. Starts and changes require separate confirmation."))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
        }
    }
    private func title(_ method: String) -> String { guard let a = GUIAction(rawValue: method) else { return method }; return state.t(a.labels.0, a.labels.1) }
    private func summary(_ method: String) -> String {
        switch GUIAction(rawValue: method) {
        case .connect: return state.t("目标实例、Guest 身份和连接已验证。", "Target instance, Guest identity and connection verified.")
        case .inspect: return state.t("已读取 Guest 环境；文件与进程结果见下方。", "Guest inspected; file and process evidence is shown below.")
        case .startFX: return state.t("已观察到 FX 宿主；请点击连接以检查 Guest 就绪状态。", "FX host observed. Connect to check Guest readiness.")
        case .steam: return state.t("Steam 已运行；未请求启动游戏。", "Steam is running; no game launch was requested.")
        case .fxState: return state.guiSnapshots[method]?["fx_host_running"]?.boolean == true ? state.t("已观察到所选 FX 宿主进程，Guest 需单独检查。", "Selected FX host observed; Guest requires a separate check.") : state.t("所选 FX 当前未运行。", "The selected FX is not running.")
        default: return state.t("已返回真实执行结果；游戏内状态见总览。", "Execution result received; see Dashboard for gameplay evidence.")
        }
    }
    private func symbol(_ a: GUIAction) -> String { switch a { case .connect: return "link"; case .inspect, .fxState: return "checklist"; default: return "play.fill" } }
    private func component(_ key: String) -> String {
        switch key {
        case "steam_files": return state.t("Steam 安装目录", "Steam installation directory")
        case "game_manifest": return state.t("游戏安装记录", "Game installation manifest")
        case "game_directory": return state.t("游戏目录", "Game directory")
        case "game_executable": return state.t("游戏程序文件", "Game executable file")
        case "proton_files": return state.t("Proton 工具文件", "Proton tool files")
        default: return state.t("FEX 组件文件", "FEX component files")
        }
    }
    private func status(_ s: GUIOperationStatus) -> String {
        switch s { case .idle: return state.t("未开始", "Not started"); case .running: return state.t("正在执行", "Running"); case .succeeded: return state.t("执行成功", "Succeeded"); case .failed: return state.t("执行失败", "Failed"); case .cancelled: return state.t("已取消", "Cancelled"); case .timedOut: return state.t("已超时", "Timed out") }
    }
    private func tone(_ s: GUIOperationStatus) -> TacticalTone { switch s { case .succeeded: return .success; case .failed, .timedOut: return .error; case .running: return .checking; default: return .neutral } }
}
