import SwiftUI

struct SidebarView: View {
    @ObservedObject var state: AppState
    var compact = false
    @FocusState private var focusedPage: Page?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !compact {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(state.t("ui.286")).font(TacticalTypography.log).tracking(1.4).foregroundStyle(c.muted)
                            Text("HELLDIVERS 2").font(.system(size: 23, weight: .black).width(.condensed)).foregroundStyle(c.text)
                            Text(state.t("ui.brand.name")).font(TacticalTypography.module).foregroundStyle(c.accent)
                                .lineLimit(2).minimumScaleFactor(0.75)
                            Text(state.t("ui.291") + " · " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"))
                                .font(TacticalTypography.caption).foregroundStyle(c.muted)
                        }.padding(16)
                    }
                    TacticalDivider()
                    VStack(spacing: 5) {
                        ForEach(Page.navigationPages) { page in
                            if page == .logs { TacticalDivider().padding(.vertical, 10) }
                            TacticalNavigationItem(number: number(page), title: state.pageTitle(page), symbol: page.symbol,
                                                   selected: visibleSelection == page, shortcut: "⌘" + String(index(page) + 1), compact: compact) {
                                state.selection = page
                            }
                            .focused($focusedPage, equals: page)
                            .accessibilityIdentifier("nav.\(page.rawValue)")
                        }
                    }.padding(compact ? 6 : 12)
                    .onMoveCommand { direction in
                        guard direction == .up || direction == .down else { return }
                        let current = index(focusedPage ?? visibleSelection)
                        let next = Page.navigationPages[(current + (direction == .up ? Page.navigationPages.count - 1 : 1)) % Page.navigationPages.count]
                        focusedPage = next; state.selection = next
                    }
                    Spacer(minLength: 24)
                    TacticalDivider()
                    VStack(alignment: .leading, spacing: 10) {
                        Image("super_earth_command_emblem").resizable().scaledToFit()
                            .frame(maxWidth: compact ? 64 : 184)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                        if !compact {
                            Text(state.t("ui.116"))
                                .font(TacticalTypography.caption.weight(.semibold)).foregroundStyle(c.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                        Image("OverviewHazardStripes").resizable().scaledToFit()
                            .frame(width: compact ? 36 : 96, height: compact ? 5 : 10)
                            .frame(maxWidth: .infinity)
                            .accessibilityHidden(true)
                    }.padding(.vertical, compact ? 8 : 16)
                    .padding(.horizontal, compact ? 0 : 16)
                }
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
            }.scrollIndicators(.hidden)
        }
        .background(c.secondary).tint(c.accent)
    }
    private var visibleSelection: Page { state.selection == .fx ? .dashboard : state.selection ?? .dashboard }
    private func index(_ page: Page) -> Int { Page.navigationPages.firstIndex(of: page) ?? 0 }
    private func number(_ page: Page) -> String { String(format: "%02d", index(page) + 1) }
}
