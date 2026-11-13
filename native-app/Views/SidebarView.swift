import SwiftUI

struct SidebarView: View {
    @ObservedObject var state: AppState
    @FocusState private var focusedPage: Page?
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Image(systemName: "globe.americas.fill").foregroundStyle(c.accent)
                    Text(state.t("ui.286")).font(TacticalTypography.log).tracking(1.4).foregroundStyle(c.muted)
                }
                Text("HELLDIVERS 2").font(.system(size: 23, weight: .black).width(.condensed)).foregroundStyle(c.text)
                Text(state.t("ui.brand.name")).font(TacticalTypography.module).foregroundStyle(c.accent)
                    .lineLimit(2).minimumScaleFactor(0.75)
                Text(state.t("ui.291")).font(TacticalTypography.caption).foregroundStyle(c.muted)
            }.padding(16)
            TacticalDivider()
            VStack(spacing: 5) {
                ForEach(Page.allCases) { page in
                    if page == .logs { TacticalDivider().padding(.vertical, 10) }
                    TacticalNavigationItem(number: number(page), title: state.pageTitle(page), symbol: page.symbol,
                                           selected: (state.selection ?? .dashboard) == page, shortcut: "⌘" + String(index(page) + 1)) {
                        state.selection = page
                    }
                    .focused($focusedPage, equals: page)
                    .accessibilityIdentifier("nav.\(page.rawValue)")
                }
            }.padding(12)
            .onMoveCommand { direction in
                guard direction == .up || direction == .down else { return }
                let current = index(focusedPage ?? state.selection ?? .dashboard)
                let next = Page.allCases[(current + (direction == .up ? Page.allCases.count - 1 : 1)) % Page.allCases.count]
                focusedPage = next; state.selection = next
            }
                }
            }.scrollIndicators(.hidden)
            TacticalDivider()
            VStack(alignment: .leading, spacing: 10) {
                TacticalEyebrow(text: state.t("ui.293"))
                Text(state.t("ui.003"))
                    .font(TacticalTypography.log).foregroundStyle(c.accent)
                Text(state.t("ui.116"))
                    .font(TacticalTypography.caption).foregroundStyle(c.muted)
            }.padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(c.secondary).tint(c.accent)
    }
    private func index(_ page: Page) -> Int { Page.allCases.firstIndex(of: page) ?? 0 }
    private func number(_ page: Page) -> String { String(format: "%02d", index(page) + 1) }
}
