import SwiftUI
import UniformTypeIdentifiers

/// Selected FX plus app-bundled launch resources; no user script directory is required.
struct RuntimeTargetPanel: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    private var resourceDiagnostics: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(JSONValue.array(state.targetInspection["resource_files"]?.array ?? [])) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    private var status: String {
        if state.fxSelection.selectedPath == nil { return state.t("ui.fx.choose") }
        if state.inspectingTarget { return state.t("ui.053") }
        if state.targetInspectionError != nil { return state.t("ui.041") }
        if state.targetInspection["archive_files_match"]?.boolean == true && state.targetInspection["fx_executable_present"]?.boolean == true {
            return state.t("ui.ux.files")
        }
        return state.targetInspection.isEmpty ? state.t("ui.208") : state.t("ui.ux.incomplete")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let path = state.fxSelection.selectedPath {
                Text(state.fxVersion + " · " + state.fxStatus).font(TacticalTypography.body)
                Text(path).font(TacticalTypography.caption).textSelection(.enabled)
            }
            summary
            DisclosureGroup(state.t("ui.ux.details")) {
                Text(state.t("ui.native.noPython")).font(TacticalTypography.caption)
                Text(LaunchResourceSummary.text).textSelection(.enabled)
                if let path = state.targetInspection["fx_path"]?.text { Text(path).textSelection(.enabled) }
                if state.targetInspection["archive_files_match"]?.boolean == false {
                    Text(state.t("ui.178")).foregroundStyle(.orange)
                    Text(resourceDiagnostics)
                        .font(TacticalTypography.log).textSelection(.enabled)
                }
                if let error = state.targetInspectionError { Text(error.message(state.languageCode)) }
                Text(state.t("ui.ux.scope")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                Button(state.t("ui.262")) { state.inspectTargetIfNeeded(force: true) }.disabled(tasks.busy || state.fxSelection.selectedPath == nil)
            }.font(TacticalTypography.caption)
        }
        .padding(10).background(.primary.opacity(0.035))
        .accessibilityIdentifier("runtime.target")
    }
    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(state.t("ui.fx.resources")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            Text(LaunchResourceSummary.text).font(TacticalTypography.body).lineLimit(1).truncationMode(.middle)
            Text(status).font(TacticalTypography.caption)
        }
    }
}

/// Path-bound resource and compatibility evidence for the Environment page.
struct FXTechnicalDetails: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    private var selected: [String: JSONValue] { state.fxSelection.selected ?? [:] }

    // Use the existing inspection result; hashing bundle resources in body blocks the main thread.
    private var resourceRows: [JSONValue] {
        state.targetInspection["resource_files"]?.array ?? []
    }
    private var preflightText: String {
        if let error = state.targetInspectionError { return error.code }
        if state.targetInspection["archive_files_match"]?.boolean == true { return state.t("ui.190") }
        if !state.targetInspection.isEmpty { return state.t("ui.fx.statusFailed") }
        return state.t("ui.208")
    }

    var body: some View {
        TacticalPanel(number: "FX", title: state.t("ui.fx.details"), symbol: "info.circle") {
            TacticalSectionHeader(number: "A", title: state.t("ui.fx.details.basic"), symbol: "shippingbox")
            if selected.isEmpty {
                Text(state.t("ui.fx.none")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            } else {
                TacticalInfoRow(title: state.t("ui.019"), value: selected["name"]?.text ?? state.t("ui.366"))
                TacticalInfoRow(title: state.t("ui.fx.version"), value: state.fxVersion)
                TacticalInfoRow(title: state.t("ui.fx.bundleId"), value: selected["bundle_identifier"]?.text ?? state.t("ui.366"))
                TacticalInfoRow(title: state.t("ui.132"), value: selected["path"]?.text ?? state.t("ui.366"))
                TacticalInfoRow(title: state.t("ui.102"), value: selected["location"]?.text ?? state.t("ui.366"))
                TacticalInfoRow(title: state.t("ui.324"),
                                value: selected["structure"]?.text == "metadata_valid" ? state.t("ui.190") : state.t("ui.368"))
                TacticalInfoRow(title: state.t("ui.fx.fileState"),
                                value: selected["identity_valid"]?.boolean == true ? state.t("ui.130") : state.t("ui.209"))
            }
            TacticalDivider()
            TacticalSectionHeader(number: "B", title: state.t("ui.fx.details.resources"), symbol: "shippingbox")
            if resourceRows.isEmpty {
                Text(state.t("ui.208")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            ForEach(Array(resourceRows.enumerated()), id: \.offset) { _, row in
                let name = row.object["file"]?.text ?? "—"
                let actual = row.object["actual_sha256"]?.text ?? ""
                let stateText = row.object["state"]?.text ?? "unknown"
                TacticalInfoRow(title: name,
                                value: stateText == "match" || stateText == "ready"
                                    ? state.t("ui.190")
                                    : stateText == "hash_mismatch" || stateText == "invalid"
                                        ? state.t("ui.fx.statusFailed")
                                        : stateText == "missing" ? state.t("ui.209") : state.t("ui.041"))
                if !actual.isEmpty {
                    Text(actual).font(TacticalTypography.log).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(1)
                }
            }
            TacticalDivider()
            TacticalSectionHeader(number: "C", title: state.t("ui.fx.details.compat"), symbol: "checklist")
            TacticalInfoRow(title: state.t("ui.fx.entryPoint"),
                            value: state.targetInspection["fx_executable_present"]?.boolean == true ? state.t("ui.130") : state.t("ui.208"))
            TacticalInfoRow(title: state.t("ui.fx.preflight"), value: preflightText)
            if let error = state.targetInspectionError {
                Text(error.message(state.languageCode)).font(TacticalTypography.caption).foregroundStyle(.red)
            }
            Text(state.t("ui.ux.scope")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            TacticalButton(title: state.t("ui.262"), symbol: "arrow.clockwise", primary: false,
                           disabledReason: tasks.busy ? state.t("ui.016") : nil) { state.inspectTargetIfNeeded(force: true) }
        }
    }
}

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

enum TacticalControlMetrics {
    static let cardRadius: CGFloat = 12
    static let buttonRadius: CGFloat = 8
    static let border: CGFloat = 1
    static let emphasisBorder: CGFloat = 2
    static let transition: Double = 0.2
}

struct TacticalCommandFrame: Shape {
    var accentsOnly = false

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: 1, dy: 1)
        let cut: CGFloat = 12
        let arm: CGFloat = 30
        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY + (accentsOnly ? arm : cut)))
        if accentsOnly { path.addLine(to: CGPoint(x: r.minX, y: r.minY + cut)) }
        path.addLine(to: CGPoint(x: r.minX + cut, y: r.minY))
        path.addLine(to: CGPoint(x: r.minX + (accentsOnly ? arm : r.width - cut), y: r.minY))
        if accentsOnly {
            path.move(to: CGPoint(x: r.maxX, y: r.maxY - arm))
        } else {
            path.addLine(to: CGPoint(x: r.maxX, y: r.minY + cut))
        }
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cut))
        path.addLine(to: CGPoint(x: r.maxX - cut, y: r.maxY))
        path.addLine(to: CGPoint(x: r.maxX - (accentsOnly ? arm : r.width - cut), y: r.maxY))
        if !accentsOnly {
            path.addLine(to: CGPoint(x: r.minX, y: r.maxY - cut))
            path.closeSubpath()
        }
        return path
    }
}

struct TacticalButtonStyle: ButtonStyle {
    var primary = false
    var emphasized = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        let c = TacticalColors(scheme: scheme)
        let surface = if !enabled { c.disabled }
            else if primary { configuration.isPressed ? c.primaryPressed : hovered ? c.primaryHover : c.yellow }
            else if configuration.isPressed { c.pressed }
            else if hovered { c.hover }
            else { emphasized ? c.selected : c.elevated }
        let shape = RoundedRectangle(cornerRadius: TacticalControlMetrics.buttonRadius)
        configuration.label.font(TacticalTypography.body.weight(.semibold))
            .foregroundStyle(primary && enabled ? c.ink : enabled ? c.text : c.muted)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 40)
            .background(surface, in: shape)
            .overlay(shape.strokeBorder(focused || (emphasized && enabled) ? c.accent : c.line,
                                        lineWidth: focused ? TacticalControlMetrics.emphasisBorder : TacticalControlMetrics.border))
            .contentShape(shape)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: TacticalControlMetrics.transition), value: hovered)
    }
}

struct TacticalButton: View {
    let title: String
    let symbol: String
    var primary = false
    var loading = false
    var disabledReason: String? = nil
    var fillsWidth = false
    var emphasized = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if loading { ProgressView().controlSize(.mini) }
                else { Image(systemName: symbol).accessibilityHidden(true) }
                Text(title)
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(TacticalButtonStyle(primary: primary, emphasized: emphasized))
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
    var compact = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isFocused) private var focused
    @State private var hovered = false
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        Button(action: action) {
            HStack(spacing: 8) {
                if !compact { Text(number).font(TacticalTypography.log).frame(width: 20, alignment: .leading) }
                Image(systemName: symbol).font(.system(size: 16, weight: .medium))
                    .frame(width: 20).accessibilityHidden(true)
                if !compact {
                    Text(title).font(TacticalTypography.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(shortcut).font(TacticalTypography.log).frame(width: 22, alignment: .trailing)
                }
            }
            .foregroundColor(selected ? c.ink : c.text)
            .frame(maxWidth: .infinity, alignment: compact ? .center : .leading)
            .padding(.horizontal, 8).padding(.vertical, 10)
            .background(selected ? c.yellow : hovered ? c.line.opacity(0.25) : c.secondary)
            .overlay(alignment: .leading) { if selected { Rectangle().fill(c.ink).frame(width: 3).padding(.vertical, 9) } }
            .overlay(Rectangle().stroke(focused ? c.accent : .clear, lineWidth: 2))
            .drawingGroup()
            .contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .help(title + " " + shortcut)
            .accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// One shared secondary-page banner. Artwork is bundled, decorative and noninteractive.
struct TacticalPageHeader: View {
    let title: String
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
                    }
                }
                // Reserve the right-hand emblem region for the artwork.
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

// Workflow illustrations never compete with controls in a narrow content area.
struct TacticalFlowArtwork<Content: View>: View {
    let asset: String
    @ViewBuilder let content: Content
    @State private var availableWidth: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        let showArt = availableWidth >= 860
        let artWidth = min(420, max(320, availableWidth * 0.36))
        HStack(alignment: .top, spacing: 24) {
            content.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .topLeading)
            if showArt {
                VStack(alignment: .trailing, spacing: 8) {
                    HStack(spacing: 5) {
                        Rectangle().fill(c.accent).frame(width: 40, height: 3)
                        Rectangle().fill(c.line).frame(height: 1)
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(c.accent)
                    }
                    Image(asset).resizable().scaledToFit().frame(width: artWidth)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.line, lineWidth: 1))
                    TacticalHazardBand().frame(width: 106, height: 9)
                }
                .frame(width: artWidth)
                .accessibilityHidden(true).allowsHitTesting(false)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                LinearGradient(colors: [c.panel.opacity(0.65), c.background, c.panel.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                TacticalFlowBackdrop().foregroundStyle(c.accent.opacity(scheme == .dark ? 0.08 : 0.11))
                GeometryReader { geometry in
                    Color.clear
                    .onAppear { availableWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { _, width in availableWidth = width }
                }
            }
        }
        .overlay(alignment: .topLeading) { Rectangle().fill(c.accent).frame(width: 58, height: 3) }
    }
}

/// Background graphics are decorative and carry no state or interaction.
private struct TacticalFlowBackdrop: View {
    var body: some View {
        Canvas { context, size in
            for index in 0..<7 {
                let x = CGFloat(index) * 105
                var path = Path(); path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + size.height * 0.55, y: 0))
                context.stroke(path, with: .foreground, lineWidth: 1)
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct TacticalHazardBand: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in
            let color = TacticalColors(scheme: scheme).accent
            for index in 0..<18 {
                let x = CGFloat(index) * 16
                var path = Path(); path.move(to: CGPoint(x: x, y: size.height)); path.addLine(to: CGPoint(x: x + 6, y: 0)); path.addLine(to: CGPoint(x: x + 13, y: 0)); path.addLine(to: CGPoint(x: x + 7, y: size.height)); path.closeSubpath()
                context.fill(path, with: .color(color))
            }
        }.clipped().accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct TacticalFlowFooter: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                TacticalHazardBand().frame(width: 132, height: 13)
                Rectangle().fill(c.accent).frame(width: 92, height: 3)
                Rectangle().fill(c.line).frame(width: 148, height: 1)
            }
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 23, weight: .bold)).foregroundStyle(c.accent)
            Rectangle().fill(c.line).frame(maxWidth: .infinity).frame(height: 1)
        }.padding(.top, 12).accessibilityHidden(true).allowsHitTesting(false)
    }
}

// Decorative marks are independent of the workflow's actual state.
struct TacticalFlowMark: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(c.accent).frame(width: 12, height: 5).rotationEffect(.degrees(-25))
            }
            Rectangle().fill(c.line).frame(height: 1)
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 11)).foregroundStyle(c.accent)
        }
        .frame(maxWidth: 180)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}

struct TacticalFlowStep: View {
    let number: String
    let title: String
    let symbol: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        HStack(spacing: 12) {
            Text(verbatim: number).font(TacticalTypography.log).foregroundStyle(c.accent).accessibilityHidden(true)
            Image(systemName: symbol).frame(width: 22).foregroundStyle(c.accent).accessibilityHidden(true)
            Text(title).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
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
        case "running_bridge": return state.t("ui.167")
        case "file_present_unverified": return state.t("ui.126")
        case "missing": return state.t("ui.210")
        case "invalid": return state.t("ui.127")
        default: return state.t("ui.368")
        }
    }
    static func name(_ name: String, _ state: AppState) -> String {
        switch name {
        case "Game components": return state.t("ui.135")
        case "FX runtime": return state.t("ui.122")
        case "gvproxy runtime": return state.t("ui.387")
        case "SSH connection": return state.t("ui.287")
        case "Multiplayer": return state.t("ui.191")
        default: return name
        }
    }
}

/// Keeps complete rows across the proposed width; never reserves empty grid slots.
struct TacticalAdaptiveLayout: Layout {
    static let compactWidth: CGFloat = 760
    var minimumWidth: CGFloat
    var maximumColumns: Int
    var fillsPartialRows = true
    var compactColumns: Int? = nil
    private let gap: CGFloat = 12
    private func columns(_ width: CGFloat, count: Int) -> Int {
        let limit = width < Self.compactWidth ? compactColumns ?? maximumColumns : maximumColumns
        let n = min(count, limit, max(1, Int((width + gap) / (minimumWidth + gap))))
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
            let usedColumns = fillsPartialRows ? row.count : cols
            let w = (width - gap * CGFloat(usedColumns - 1)) / CGFloat(usedColumns)
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
        HStack {
            Spacer(minLength: 0)
            TacticalButton(title: state.t("ui.262"), symbol: "arrow.clockwise",
                           loading: state.refreshing,
                           disabledReason: tasks.busy ? state.t("ui.016") : nil) {
                state.refresh()
            }
            .help(state.t("ui.263"))
            .accessibilityIdentifier("refresh")
        }
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
        case .unchecked: return state.t("ui.208")
        case .checking: return state.t("ui.053")
        case .normal: return state.t("ui.206")
        case .action: return state.t("ui.006")
        case .failed: return state.t("ui.050")
        case .uncertain: return state.t("ui.041")
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
    private let methods: [GUIAction] = [.inspect, .connect, .fxState]
    private var facts: [String: JSONValue] { state.latestGUIEvidence }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                TacticalButton(title: state.t("ui.159"), symbol: "checklist", primary: true,
                               loading: state.guiRecords[GUIAction.inspect.rawValue]?.status == .running,
                               disabledReason: tasks.busy ? state.t("ui.224") : nil) { state.perform(.inspect) }
                Spacer()
            }
            Text(state.t("ui.379")).font(TacticalTypography.caption).foregroundStyle(.secondary)
            TacticalAdaptiveLayout(minimumWidth: 145, maximumColumns: 4) {
                TacticalMetric(title: "FX Runtime", value: booleanFact("fx_host_running"), symbol: "shippingbox")
                TacticalMetric(title: state.t("ui.144"), value: booleanFact("ssh_connected"), symbol: "link")
                TacticalMetric(title: "Steam", value: processFact("steam_process_count"), symbol: "play.circle")
                TacticalMetric(title: state.t("ui.138"), value: fileFact("game_executable"), symbol: "folder")
            }
            GUIActionFeedback(state: state, methods: methods.map(\.rawValue))
            DisclosureGroup(state.t("ui.080")) {
                TacticalInfoRow(title: state.t("ui.302"), value: state.runtimeRoot.isEmpty ? state.t("ui.062") : URL(fileURLWithPath: state.runtimeRoot).lastPathComponent)
                HStack {
                    Button(state.t("ui.079")) { state.perform(.connect) }
                    Button(state.t("ui.048")) { state.perform(.fxState) }
                }.disabled(tasks.busy)
                if let os = facts["guest_os"]?.text { TacticalInfoRow(title: state.t("ui.149"), value: os) }
                ForEach(["steam_files","game_manifest","game_directory","game_executable","proton_files","fex_files"], id: \.self) { key in
                    TacticalInfoRow(title: component(key), value: fileFact(key))
                }
                Text(state.t("ui.172"))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func booleanFact(_ key: String) -> String {
        guard let value = facts[key]?.boolean else { return state.t("ui.208") }
        return value ? state.t("ui.377") : state.t("ui.214")
    }
    private func processFact(_ key: String) -> String {
        guard let n = facts[key]?.integer else { return state.t("ui.208") }
        return n > 0 ? state.t("ui.237") : state.t("ui.201")
    }
    private func fileFact(_ key: String) -> String {
        guard let value = facts["components"]?.object[key]?.boolean else { return state.t("ui.208") }
        return value ? state.t("ui.130") : state.t("ui.209")
    }
    private func component(_ key: String) -> String {
        switch key {
        case "steam_files": return state.t("ui.321")
        case "game_manifest": return state.t("ui.139")
        case "game_directory": return state.t("ui.136")
        case "game_executable": return state.t("ui.137")
        case "proton_files": return state.t("ui.238")
        default: return state.t("ui.115")
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
                    Text(GUIAction(rawValue: record.method).map { state.t($0.labelKey) } ?? record.method).font(TacticalTypography.body.weight(.semibold))
                    TacticalStatusBadge(text: record.status.title(state), tone: record.status == .succeeded ? .success : record.error == nil ? .neutral : .error)
                    Spacer()
                    if record.status == .running { Button(state.t("ui.037")) { state.tasks.cancel() } }
                }
                if let error = record.error {
                    Text(error.message(state.languageCode)).font(TacticalTypography.body)
                    DisclosureGroup(state.t("ui.381")) {
                        Text(error.code + " · " + (error.details["summary"]?.text ?? "")).font(TacticalTypography.log).textSelection(.enabled)
                        Button(state.t("ui.271")) { state.operationSelection = NativeOperation(method: record.method) }
                    }
                } else if record.status == .succeeded {
                    Text(state.t("ui.004"))
                        .font(TacticalTypography.caption)
                }
                DisclosureGroup(state.t("ui.005")) {
                    TacticalInfoRow(title: state.t("ui.319"), value: record.startedAt.formatted(date: .omitted, time: .standard))
                    if let end = record.endedAt { TacticalInfoRow(title: state.t("ui.128"), value: end.formatted(date: .omitted, time: .standard)) }
                    Button(state.t("ui.380")) { state.selection = .logs }
                }
            }.padding(14).background(.primary.opacity(0.035))
        }
    }
}

extension GUIOperationStatus {
    @MainActor func title(_ state: AppState) -> String {
        switch self {
        case .idle: return state.t("ui.216")
        case .running: return state.t("ui.281")
        case .succeeded: return state.t("ui.325")
        case .failed: return state.t("ui.125")
        case .cancelled: return state.t("ui.039")
        case .timedOut: return state.t("ui.359")
        }
    }
}
