import SwiftUI
import AppKit
import UniformTypeIdentifiers

private struct LogExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self)
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

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
    @State private var autoScroll = true
    @State private var showExporter = false
    @State private var exportFailed = false
    @State private var exportText = ""
    @Environment(\.colorScheme) private var scheme
    private var lines: [SessionLogLine] {
        let swift = state.sessionLogs.enumerated().map { index, text in
            let parts = text.components(separatedBy: "  ")
            return SessionLogLine(id: "swift-\(index)", time: parts.count > 1 ? parts[0] : "—", source: "App", message: state.credentials.redactor.text(parts.count > 1 ? parts.dropFirst().joined(separator: "  ") : text), level: "UNCLASSIFIED")
        }
        let bridge = state.rows("get_logs", "entries").enumerated().map { index, row in
            let raw = row["level"]?.text?.uppercased() ?? "UNCLASSIFIED"
            let severity = ["INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG"].contains(raw) ? raw : "UNCLASSIFIED"
            return SessionLogLine(id: "core-\(index)", time: row["at"]?.text ?? "—", source: "Core", message: state.credentials.redactor.text(row["message"]?.text ?? ""), level: severity)
        }
        let runtime = state.runtimeLogs.enumerated().map { index, row in
            SessionLogLine(id: row["id"]?.text ?? "runtime-\(index)", time: row["at"]?.text ?? "—", source: row["source"]?.text ?? "Core", message: state.credentials.redactor.text((row["message"]?.text ?? "") + " " + (row["status"]?.text ?? "")), level: row["level"]?.text ?? "UNCLASSIFIED")
        }
        return (swift + bridge + runtime).sorted { $0.time < $1.time }
    }
    private var filtered: [SessionLogLine] {
        lines.filter { (level == "ALL" || $0.level == level) && (search.isEmpty || ($0.time + $0.source + $0.message).localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        let c = TacticalColors(scheme: scheme)
        VStack(alignment: .leading, spacing: 18) {
            TacticalPageHeader(title: state.t("ui.306"), refreshState: state)
            TacticalWarningBanner(text: state.t("ui.017"))
            if exportFailed { TacticalWarningBanner(text: state.t("ui.logs.exportFailed"), isError: true) }
            DisclosureGroup(state.t("ui.096")) { LegacyOperationsView(state: state, scope: "logs") }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { filters; searchField; logActions }
                VStack(alignment: .leading, spacing: 12) { searchField; HStack { filters; Spacer(minLength: 0); logActions } }
            }
            Toggle(state.t("ui.logs.autoScroll"), isOn: $autoScroll).toggleStyle(.checkbox)
            ScrollViewReader { proxy in
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filtered) { row in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(LogTimestamp.display(row.time)).foregroundStyle(c.muted)
                            Text(row.source).foregroundStyle(c.accent)
                            Spacer()
                            TacticalStatusBadge(text: row.level == "UNCLASSIFIED" ? state.t("ui.364") : row.level, tone: row.tone)
                        }
                        Text(LogTimestamp.displayTimestamps(in: row.message)).foregroundStyle(c.text).textSelection(.enabled)
                    }.font(TacticalTypography.log).padding(12)
                    TacticalDivider()
                }
                if filtered.isEmpty {
                    Text(state.t("ui.200"))
                        .foregroundStyle(c.muted).padding(20)
                }
                Color.clear.frame(height: 1).id("log-bottom")
            }.frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
            }
            .frame(height: 420)
            .onAppear { if autoScroll { proxy.scrollTo("log-bottom", anchor: .bottom) } }
            .onChange(of: state.runtimeLogs.last?["id"]?.text ?? state.runtimeLogs.last?["at"]?.text) { _, _ in
                if autoScroll { proxy.scrollTo("log-bottom", anchor: .bottom) }
            }
            .onChange(of: state.sessionLogs.last) { _, _ in
                if autoScroll { proxy.scrollTo("log-bottom", anchor: .bottom) }
            }
            .onChange(of: autoScroll) { _, enabled in if enabled { proxy.scrollTo("log-bottom", anchor: .bottom) } }
            }
                .background(c.secondary, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(c.line))
                .accessibilityIdentifier("logs.content")
        }
        .fileExporter(isPresented: $showExporter, document: LogExportDocument(text: exportText), contentType: .plainText,
                      defaultFilename: "HD2FXNative-logs") { result in
            if case .failure = result { exportFailed = true }
        }
    }
    private var logActions: some View {
        HStack(spacing: 8) {
            copyButton
            TacticalButton(title: state.t("ui.logs.export"), symbol: "square.and.arrow.up", disabledReason: filtered.isEmpty ? state.t("ui.197") : nil) {
                exportText = state.t("ui.logs.exportHeader") + "\n" + rawFilteredText
                exportFailed = false
                showExporter = true
            }
        }
    }
    private var filters: some View {
        Picker(state.t("ui.182"), selection: $level) {
            Text(state.t("ui.010")).tag("ALL")
            Text(state.t("ui.364")).tag("UNCLASSIFIED")
            ForEach(["INFO", "SUCCESS", "WARNING", "ERROR", "DEBUG"], id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 210)
    }
    private var searchField: some View {
        TextField(state.t("ui.298"), text: $search).textFieldStyle(.roundedBorder)
            .accessibilityLabel(state.t("ui.297"))
    }
    private var copyButton: some View {
        TacticalButton(title: state.t("ui.081"), symbol: "doc.on.doc", disabledReason: filtered.isEmpty ? state.t("ui.197") : nil) {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(rawFilteredText, forType: .string)
        }
    }
    private var rawFilteredText: String {
        state.credentials.redactor.text(filtered.map { "\($0.time) [\($0.source)] [\($0.level)] \($0.message)" }.joined(separator: "\n"))
    }
}
