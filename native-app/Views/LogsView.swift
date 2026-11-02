import SwiftUI

struct LogsView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Text(state.t("显示本次 App 通信与只读 Bridge 日志；游戏日志接口尚未实现（NOT_IMPLEMENTED）。", "Shows this app's communication and read-only bridge logs. Game log access is NOT_IMPLEMENTED."))
            .foregroundStyle(.secondary)
        ScrollView([.horizontal, .vertical]) {
            Text(state.logText.isEmpty ? state.t("暂无会话日志", "No session logs yet") : state.logText)
                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                .frame(maxWidth: .infinity, minHeight: 280, alignment: .topLeading).padding(12)
        }
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityIdentifier("logs.content")
    }
}
