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
        .background(c.panel)
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
                Text(title).foregroundStyle(c.muted)
                Spacer(minLength: 6)
                Text(value).foregroundStyle(c.text).multilineTextAlignment(.trailing)
            }.fixedSize(horizontal: true, vertical: false)
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
