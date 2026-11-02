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

struct SuperEarthGlobeDecoration: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let rect = CGRect(x: 10, y: 3, width: 80, height: 80)
            let color = TacticalColors(scheme: scheme).accent.opacity(0.28)
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: 1)
            for fraction in [0.25, 0.55] {
                context.stroke(Path(ellipseIn: CGRect(x: 50 - 40 * fraction, y: 3, width: 80 * fraction, height: 80)), with: .color(color), lineWidth: 0.7)
                context.stroke(Path(ellipseIn: CGRect(x: 10, y: 43 - 40 * fraction, width: 80, height: 80 * fraction)), with: .color(color), lineWidth: 0.7)
            }
        }.frame(width: 100, height: 86).accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct TacticalPageHeader: View {
    let number: String
    let title: String
    let section: String
    var refreshState: AppState? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 10) {
                    TacticalEyebrow(text: number + " / " + section)
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            pageTitle
                            if let refreshState { TacticalRefreshButton(state: refreshState, tasks: refreshState.tasks) }
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            pageTitle
                            if let refreshState { TacticalRefreshButton(state: refreshState, tasks: refreshState.tasks) }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                SuperEarthGlobeDecoration()
            }
            Rectangle().fill(c.yellow).frame(height: 2)
        }
    }
    private var pageTitle: some View {
        Text(title).font(TacticalTypography.page).foregroundStyle(TacticalColors(scheme: scheme).text)
            .accessibilityIdentifier("page.title").accessibilityAddTraits(.isHeader)
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
        .overlay(Rectangle().stroke(.secondary.opacity(0.4)))
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
