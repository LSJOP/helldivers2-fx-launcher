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
    private var methods: [GUIAction] { environment ? [.inspect, .connect] : [.startFX, .steam, .fxState, .connect] }
    private var facts: [String: JSONValue] { state.latestGUIEvidence }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if environment {
                HStack {
                    TacticalButton(title: state.t("一键检测", "Inspect environment"), symbol: "checklist", primary: true,
                        loading: state.guiRecords[GUIAction.inspect.rawValue]?.status == .running, disabledReason: tasks.busy ? state.t("操作执行中", "Operation in progress") : nil) { state.perform(.inspect) }
                    Spacer()
                }
                Text(state.t("自动验证所选虚拟机身份与连接，并只读检查运行环境；不会启动虚拟机或修改配置。", "Verify the selected Guest identity and connection, then inspect its environment read-only. Does not start the VM or change configuration."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
                TacticalAdaptiveLayout(minimumWidth: 145, maximumColumns: 4) {
                    TacticalMetric(title: "FX Runtime", value: booleanFact("fx_host_running"), symbol: "shippingbox")
                    TacticalMetric(title: state.t("虚拟机连接", "Guest connection"), value: booleanFact("ssh_connected"), symbol: "link")
                    TacticalMetric(title: "Steam", value: processFact("steam_process_count"), symbol: "play.circle")
                    TacticalMetric(title: state.t("游戏文件", "Game files"), value: fileFact("game_executable"), symbol: "folder")
                }
            } else {
                TacticalAdaptiveLayout(minimumWidth: 245, maximumColumns: 2) {
                    actionCard(.startFX, description: state.t("使用已验证的原入口；已运行则检查并复用。", "Use the original verified entry; check and reuse a running instance."))
                    unavailableCard(state.t("停止 FX", "Stop FX"), symbol: "stop.fill")
                    unavailableCard(state.t("重启 FX", "Restart FX"), symbol: "arrow.clockwise")
                    actionCard(.steam, description: state.t("后台连接并受控启动 Steam，不请求游戏启动。", "Connect in the background and start Steam through the controlled backend, without launching the game."))
                }
            }
            GUIActionFeedback(state: state, methods: methods.map(\.rawValue))
            DisclosureGroup(state.t("连接与检测详情", "Connection and inspection details")) {
                TacticalInfoRow(title: state.t("所选环境", "Selected environment"), value: state.runtimeRoot.isEmpty ? state.t("尚未选择，首次操作时选择", "Choose on first action") : URL(fileURLWithPath: state.runtimeRoot).lastPathComponent)
                HStack {
                    Button(state.t("连接虚拟机", "Connect virtual machine")) { state.perform(.connect) }
                    Button(state.t("检查 FX 状态", "Check FX status")) { state.perform(.fxState) }
                }.disabled(tasks.busy)
                if !environment { Button(state.t("前往游戏启动", "Go to game launch")) { state.selection = .dashboard } }
                if let os = facts["guest_os"]?.text { TacticalInfoRow(title: state.t("Guest 系统", "Guest system"), value: os) }
                ForEach(["steam_files","game_manifest","game_directory","game_executable","proton_files","fex_files"], id: \.self) { key in
                    TacticalInfoRow(title: component(key), value: fileFact(key))
                }
                Text(state.t("仅表示最近一次检查。文件存在不等于可运行；进程存在不等于进入游戏。", "Last inspection only. File presence does not establish readiness; a process does not prove gameplay."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func booleanFact(_ key: String) -> String {
        guard let value = facts[key]?.boolean else { return state.t("未检查", "Not checked") }
        return value ? state.t("已验证 · 最近检查", "Verified · Last check") : state.t("未运行／未连接", "Not running / connected")
    }
    private func processFact(_ key: String) -> String {
        guard let n = facts[key]?.integer else { return state.t("未检查", "Not checked") }
        return n > 0 ? state.t("进程已观察到", "Process observed") : state.t("未发现进程", "No process found")
    }
    private func fileFact(_ key: String) -> String {
        guard let value = facts["components"]?.object[key]?.boolean else { return state.t("未检查", "Not checked") }
        return value ? state.t("已发现 · 文件证据", "Found · File evidence") : state.t("限定位置未发现", "Not found in checked locations")
    }
    private func actionCard(_ action: GUIAction, description: String) -> some View {
        TacticalPanel(number: "", title: state.t(action.labels.0, action.labels.1), symbol: "play.circle") {
            Text(description).font(TacticalTypography.caption)
            Text(state.guiRecords[action.rawValue].map { $0.status.title(state) } ?? state.t("未开始", "Not started")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            TacticalButton(title: state.t("启动", "Start"), symbol: "play.fill", primary: true, loading: state.guiRecords[action.rawValue]?.status == .running,
                disabledReason: tasks.busy ? state.t("操作执行中", "Operation in progress") : nil) { state.perform(action) }
        }
    }
    private func unavailableCard(_ title: String, symbol: String) -> some View {
        TacticalPanel(number: "", title: title, symbol: symbol) {
            Text(state.t("暂不可用：尚无经验证的正常退出接口。请在 FX 中正常退出。", "Unavailable: a graceful-exit backend is not verified. Quit normally in FX."))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            TacticalButton(title: state.t("不可用", "Unavailable"), symbol: symbol, disabledReason: state.t("等待安全退出后端", "Awaiting a graceful-exit backend")) {}
        }
    }
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
}

struct GUIActionFeedback: View {
    @ObservedObject var state: AppState
    let methods: [String]
    private var record: GUIOperationRecord? { state.guiRecords.values.filter { $0.target == state.runtimeRoot && methods.contains($0.method) }.max { $0.startedAt < $1.startedAt } }
    var body: some View {
        if let record {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if record.status == .running { ProgressView().controlSize(.small) }
                    Text(GUIAction(rawValue: record.method).map { state.t($0.labels.0, $0.labels.1) } ?? record.method).font(TacticalTypography.body.weight(.semibold))
                    TacticalStatusBadge(text: record.status.title(state), tone: record.status == .succeeded ? .success : record.error == nil ? .neutral : .error)
                    Spacer()
                    if record.status == .running { Button(state.t("取消", "Cancel")) { state.tasks.cancel() } }
                }
                if let error = record.error {
                    Text(error.message(state.chinese)).font(TacticalTypography.body)
                    DisclosureGroup(state.t("查看原因", "View reason")) {
                        Text(error.code + " · " + (error.details["summary"]?.text ?? "")).font(TacticalTypography.log).textSelection(.enabled)
                        Button(state.t("处理此问题", "Resolve this issue")) { state.operationSelection = NativeOperation(method: record.method) }
                    }
                } else if record.status == .succeeded {
                    Text(state.t("操作已完成；请查看对应状态证据。", "Action completed; review the corresponding evidence."))
                        .font(TacticalTypography.caption)
                }
                DisclosureGroup(state.t("操作详情", "Action details")) {
                    TacticalInfoRow(title: state.t("开始", "Started"), value: record.startedAt.formatted(date: .omitted, time: .standard))
                    if let end = record.endedAt { TacticalInfoRow(title: state.t("结束", "Finished"), value: end.formatted(date: .omitted, time: .standard)) }
                    Button(state.t("查看高级日志", "View advanced logs")) { state.selection = .logs }
                }
            }.padding(14).background(.primary.opacity(0.035))
        }
    }
}

extension GUIOperationStatus {
    @MainActor func title(_ state: AppState) -> String {
        switch self {
        case .idle: return state.t("未开始", "Not started")
        case .running: return state.t("正在执行", "Running")
        case .succeeded: return state.t("执行成功", "Succeeded")
        case .failed: return state.t("执行失败", "Failed")
        case .cancelled: return state.t("已取消", "Cancelled")
        case .timedOut: return state.t("已超时", "Timed out")
        }
    }
}
