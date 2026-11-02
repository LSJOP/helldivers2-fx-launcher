import SwiftUI
import AppKit

private struct SessionLogLine: Identifiable {
    let id: String
    let time: String
    let source: String
    let message: String
    let level: String
    var tone: TacticalTone {
        switch level { case "SUCCESS": return .success; case "WARNING": return .warning; case "ERROR": return .error; default: return .neutral }
    }
}

struct LogsView: View {
    @ObservedObject var state: AppState
    @State private var search = ""
    @State private var level = "ALL"
    @Environment(\.colorScheme) private var scheme
    private var lines: [SessionLogLine] {
        let swift = state.sessionLogs.enumerated().map { index, text in
            let parts = text.components(separatedBy: "  ")
            return SessionLogLine(id: "swift-\(index)", time: parts.count > 1 ? parts[0] : "—", source: "App", message: parts.count > 1 ? parts.dropFirst().joined(separator: "  ") : text, level: "UNCLASSIFIED")
        }
        let bridge = state.rows("get_logs", "entries").enumerated().map { index, row in
            let raw = row["level"]?.text?.uppercased() ?? "UNCLASSIFIED"
            let severity = ["INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG"].contains(raw) ? raw : "UNCLASSIFIED"
            return SessionLogLine(id: "bridge-\(index)", time: row["at"]?.text ?? "—", source: "Bridge", message: row["message"]?.text ?? "", level: severity)
        }
        let runtime = state.runtimeLogs.enumerated().map { index, row in
            SessionLogLine(id: "runtime-\(index)", time: row["at"]?.text ?? "—", source: row["source"]?.text ?? "Core", message: (row["message"]?.text ?? "") + " " + (row["status"]?.text ?? ""), level: row["level"]?.text ?? "UNCLASSIFIED")
        }
        return swift + bridge + runtime
    }
    private var filtered: [SessionLogLine] {
        lines.filter { (level == "ALL" || $0.level == level) && (search.isEmpty || ($0.time + $0.source + $0.message).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 18) {
            TacticalPageHeader(number: "04", title: state.t("运行日志", "Session logs"), section: state.pageTitle(.logs))
            TacticalWarningBanner(text: state.t("仅本次会话 App 与 Bridge 日志。原始日志没有等级字段时显示“未标级”，不会推断成功等级。", "App and bridge logs from this session only. Entries without an explicit severity remain unclassified; success is not inferred."))
            LegacyOperationsView(state: state, scope: "logs")
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { filters; searchField; copyButton }
                VStack(alignment: .leading, spacing: 12) { filters; HStack { searchField; copyButton } }
            }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(filtered) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(row.time).foregroundStyle(c.muted)
                            Text(row.source).foregroundStyle(c.accent)
                            Spacer()
                            TacticalStatusBadge(text: row.level == "UNCLASSIFIED" ? state.t("未标级", "Unclassified") : row.level, tone: row.tone)
                        }
                        Text(row.message).foregroundStyle(c.text).textSelection(.enabled)
                    }.font(TacticalTypography.log).padding(12)
                    TacticalDivider()
                }
                if filtered.isEmpty {
                    Text(state.t("没有匹配的会话日志", "No matching session entries"))
                        .foregroundStyle(c.muted).padding(20)
                }
            }.frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
                .background(c.secondary, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(c.line))
                .accessibilityIdentifier("logs.content")
        }
    }
    private var filters: some View {
        Picker(state.t("等级", "Level"), selection: $level) {
            Text(state.t("全部", "All")).tag("ALL")
            Text(state.t("未标级", "Unclassified")).tag("UNCLASSIFIED")
            ForEach(["INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG"], id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 210)
    }
    private var searchField: some View {
        TextField(state.t("搜索日志…", "Search logs…"), text: $search).textFieldStyle(.roundedBorder)
            .accessibilityLabel(state.t("搜索日志", "Search logs"))
    }
    private var copyButton: some View {
        TacticalButton(title: state.t("复制", "Copy"), symbol: "doc.on.doc", disabledReason: filtered.isEmpty ? state.t("没有可复制的日志", "No entries to copy") : nil) {
            let text = filtered.map { "\($0.time) [\($0.source)] [\($0.level)] \($0.message)" }.joined(separator: "\n")
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(state.credentials.redactor.text(text), forType: .string)
        }
    }
}
