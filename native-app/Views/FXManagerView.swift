import SwiftUI
import UniformTypeIdentifiers

struct FXManagerView: View {
    @ObservedObject var state: AppState
    @State private var locatingFX = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.124"))
            if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
                TacticalWarningBanner(text: scanWarning + " " + state.t("ui.357"))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(state.fxStatus)
                HStack {
                    Button(state.t("ui.fx.rescan")) { state.scanFX() }.disabled(state.tasks.busy)
                    Button(state.t("ui.fx.locate")) { locatingFX = true }.disabled(state.tasks.busy)
                }
            }
            GUIOperationsPanel(state: state, tasks: state.tasks, environment: false)
            if state.fxSelectionIssue { TacticalWarningBanner(text: state.t("ui.fx.invalid")) }
            let candidates = state.rows("list_fx_versions", "candidates")
            if candidates.isEmpty {
                TacticalWarningBanner(text: state.t("ui.fx.none"))
            }
            TacticalAdaptiveLayout(minimumWidth: 255, maximumColumns: 2) {
                ForEach(candidates, id: \.fxCandidatePath) { row in
                    TacticalPanel(number: "FX", title: "FX " + version(row), symbol: "shippingbox") {
                        if state.fxSelection.selectedPath == row["path"]?.text {
                            TacticalStatusBadge(text: state.t(state.fxSelection.automatic ? "ui.fx.auto" : "ui.fx.default"))
                            Text(state.fxStatus).font(TacticalTypography.caption)
                        } else if row["identity_valid"]?.boolean == true, let path = row["path"]?.text {
                            Button(state.t("ui.fx.setDefault")) { state.selectFX(path) }.disabled(state.tasks.busy)
                        } else { TacticalStatusBadge(text: state.t("ui.368")) }
                        if row["local_test_copy"]?.boolean == true {
                            Text(state.t("ui.fx.localTestCopy")).font(TacticalTypography.caption).foregroundStyle(.secondary)
                        }
                        TacticalInfoRow(title: state.t("ui.019"), value: row["path"]?.text.map { URL(fileURLWithPath: $0).lastPathComponent } ?? state.t("ui.366"))
                        DisclosureGroup(state.t("ui.setup.details")) {
                            TacticalInfoRow(title: state.t("ui.132"), value: row["path"]?.text ?? state.t("ui.366"))
                            TacticalInfoRow(title: state.t("ui.324"), value: row["structure"]?.text == "metadata_valid" ? state.t("ui.190") : state.t("ui.368"))
                        }
                    }
                }
            }
            DisclosureGroup(state.t("ui.setup.details")) { FXTechnicalDetails(state: state, tasks: state.tasks) }
            DisclosureGroup(state.t("ui.095")) { LegacyOperationsView(state: state, scope: "fx") }

        }
        .fileImporter(isPresented: $locatingFX, allowedContentTypes: [.applicationBundle]) { result in
            if case .success(let url) = result { state.scanFX(manualPath: url.path) }
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
