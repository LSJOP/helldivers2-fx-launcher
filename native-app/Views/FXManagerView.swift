import SwiftUI

struct FXManagerView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.124"), refreshState: state)
            GUIOperationsPanel(state: state, tasks: state.tasks, environment: false)
            if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
                TacticalWarningBanner(text: scanWarning + " " + state.t("ui.357"))
            }
            let candidates = state.rows("list_fx_versions", "candidates")
            if candidates.isEmpty {
                TacticalWarningBanner(text: state.t("ui.211"))
            }
            TacticalAdaptiveLayout(minimumWidth: 255, maximumColumns: 2) {
                ForEach(candidates, id: \.fxCandidatePath) { row in
                    TacticalPanel(number: "FX", title: "FX " + version(row), symbol: "shippingbox") {
                        TacticalStatusBadge(text: state.t("ui.101"))
                        TacticalInfoRow(title: state.t("ui.019"), value: row["path"]?.text.map { URL(fileURLWithPath: $0).lastPathComponent } ?? state.t("ui.366"))
                        TacticalInfoRow(title: state.t("ui.102"), value: row["location"]?.text ?? state.t("ui.366"))
                        TacticalInfoRow(title: state.t("ui.132"), value: row["path"]?.text ?? state.t("ui.366"))
                        TacticalDivider()
                        TacticalInfoRow(title: state.t("ui.165"), value: state.t("ui.131"))
                        TacticalInfoRow(title: state.t("ui.324"), value: row["structure"]?.text == "metadata_valid" ? state.t("ui.190") : state.t("ui.368"))
                        TacticalDivider()
                        TacticalInfoRow(title: state.t("ui.235"), value: state.t("ui.044"))
                        TacticalInfoRow(title: "Guest", value: state.t("ui.043"))
                        TacticalInfoRow(title: state.t("ui.103"), value: state.t("ui.011"))
                    }
                }
            }
            DisclosureGroup(state.t("ui.095")) { LegacyOperationsView(state: state, scope: "fx") }
            TacticalPanel(number: "i", title: state.t("ui.163"), symbol: "info.circle") {
                Text(state.t("ui.257"))
                    .font(TacticalTypography.body)
            }
        }
    }
    private func version(_ row: [String: JSONValue]) -> String {
        let value = row["version"]?.text
        return value == nil || value == "unknown" ? state.t("ui.366") : value!
    }
    private var scanWarning: String {
        let issues = state.results["list_fx_versions"]?["issues"]?.array.compactMap(\.text) ?? []
        return issues.contains("DIRECTORY_UNAVAILABLE")
            ? state.t("ui.227")
            : state.t("ui.228")
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    var fxCandidatePath: String { self["path"]?.text ?? "unknown" }
}
