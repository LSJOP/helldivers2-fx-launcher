import SwiftUI

struct GamePerformanceView: View {
    @ObservedObject var state: AppState
    private let keys = ["cpus", "memMiB", "vulkanDriver", "metalHUD", "superResolution"]
    private var snapshot: [String: JSONValue] { state.performanceSnapshot }
    private var hardware: [String: JSONValue] { snapshot["hardware"]?.object ?? [:] }
    private var current: [String: JSONValue] { snapshot["current"]?.object ?? [:] }
    private var plan: GamePerformanceInferenceService.Plan { GamePerformanceInferenceService().infer(snapshot) }
    private var reading: Bool { state.guiRecords["read_performance"]?.status == .running }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.134"))
            TacticalButton(title: state.t("ui.243"), symbol: "arrow.clockwise", primary: true,
                loading: reading, disabledReason: state.tasks.busy ? state.t("ui.224") : nil) { state.runOperation("read_performance") }
            if let record = state.guiRecords["read_performance"] {
                TacticalStatusBadge(text: record.status.title(state), tone: record.error == nil ? .neutral : .error)
                if let error = record.error { TacticalWarningBanner(text: error.message(state.languageCode), isError: true) }
            }
            TacticalPanel(number: "A", title: state.t("ui.087"), symbol: "cpu") {
                TacticalAdaptiveLayout(minimumWidth: 155, maximumColumns: 2) {
                    TacticalMetric(title: state.t("ui.058"), value: hardware["chip"]?.text ?? unknown, symbol: "cpu")
                    TacticalMetric(title: state.t("ui.036"), value: number("cpu_cores"), symbol: "cpu")
                    TacticalMetric(title: state.t("ui.133"), value: number("gpu_cores"), symbol: "square.stack.3d.up")
                    TacticalMetric(title: state.t("ui.365"), value: memory, symbol: "memorychip")
                }
                TacticalInfoRow(title: "macOS", value: hardware["os_version"]?.text ?? unknown)
                Text(state.t("ui.250"))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            TacticalPanel(number: "B", title: state.t("ui.086"), symbol: "slider.horizontal.3") {
                Text(state.t("ui.256"))
                ForEach(keys, id: \.self) { key in TacticalInfoRow(title: label(key), value: GamePerformanceInferenceService.render(current[key])) }
                if !(snapshot["read_errors"]?.array.isEmpty ?? true) { TacticalWarningBanner(text: state.t("ui.313")) }
            }
            TacticalPanel(number: "C", title: state.t("ui.260"), symbol: "lightbulb") {
                TacticalStatusBadge(text: plan.kind == .localBaseline ? state.t("ui.184") : state.t("ui.204"), tone: .warning)
                Text(state.t("ui.337"))
                if plan.kind == .experimental {
                    TacticalWarningBanner(text: state.t("ui.111"))
                }
                Text(state.t("ui.277"))
                    .font(TacticalTypography.caption)
            }
            TacticalPanel(number: "D", title: state.t("ui.097"), symbol: "list.bullet.rectangle") {
                ForEach(keys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(label(key)).font(TacticalTypography.body.weight(.semibold))
                            Spacer()
                            Text(difference(key)).font(TacticalTypography.caption)
                        }
                        TacticalInfoRow(title: state.t("ui.090"), value: GamePerformanceInferenceService.render(current[key]) + " → " + GamePerformanceInferenceService.render(plan.reference[key]))
                        Text(parameterNote(key)).font(TacticalTypography.caption).foregroundStyle(.secondary)
                        Text("performance_profile.SETTINGS · " + key).font(TacticalTypography.log).foregroundStyle(.secondary)
                        TacticalDivider()
                    }
                }
                Text(state.t("ui.349"))
                    .font(TacticalTypography.caption)
            }
            TacticalPanel(number: "E", title: state.t("ui.021"), symbol: "arrow.uturn.backward") {
                TacticalWarningBanner(text: state.t("ui.254"))
                HStack {
                    TacticalButton(title: state.t("ui.023"), symbol: "checkmark", disabledReason: state.t("ui.202")) {}
                    TacticalButton(title: state.t("ui.273"), symbol: "arrow.uturn.backward", disabledReason: state.t("ui.203")) {}
                }
            }
        }
        .task { if snapshot.isEmpty && !state.tasks.busy { state.runOperation("read_performance") } }
    }
    private var unknown: String { state.t("ui.367") }
    private func number(_ key: String) -> String { hardware[key]?.integer.map(String.init) ?? unknown }
    private var memory: String { guard let bytes = hardware["memory_bytes"]?.integer else { return unknown }; return String(format: "%g GiB", Double(bytes) / pow(1024, 3)) }
    private func difference(_ key: String) -> String {
        guard let differs = GamePerformanceInferenceService.differs(current[key], plan.reference[key]) else { return state.t("ui.040") }
        return differs ? state.t("ui.098") : state.t("ui.294")
    }
    private func label(_ key: String) -> String {
        switch key {
        case "cpus": return state.t("ui.382")
        case "memMiB": return state.t("ui.145")
        case "vulkanDriver": return state.t("ui.383")
        case "metalHUD": return state.t("ui.229")
        default: return state.t("ui.327")
        }
    }
    private func parameterNote(_ key: String) -> String {
        if ["cpus", "memMiB"].contains(key) {
            return state.t("ui.230")
        }
        return state.t("ui.129")
    }
}
