import SwiftUI

struct GamePerformanceView: View {
    @ObservedObject var state: AppState
    private let keys = ["cpus", "memMiB", "vulkanDriver", "metalHUD", "superResolution"]
    private var snapshot: [String: JSONValue] { state.performanceSnapshot }
    private var hardware: [String: JSONValue] { snapshot["hardware"]?.object ?? [:] }
    private var configuration: [String: JSONValue] { state.performanceConfiguration }
    private var rules: [String: JSONValue] { configuration["capabilities"]?.object ?? [:] }
    private var current: [String: JSONValue] { configuration["current"]?.object ?? snapshot["current"]?.object ?? [:] }
    private func l(_ text: String) -> String { state.t(text) }
    private func failureMessage(_ code: String) -> String {
        switch code {
        case "PERF_RUNNING": return l("ui.integrated.026")
        case "PERF_CONFLICT": return l("ui.integrated.027")
        case "PERF_VERSION": return l("ui.integrated.028")
        case "PERF_BACKUP": return l("ui.integrated.029")
        case "PERF_RANGE", "PERF_PARAMETER": return l("ui.integrated.030")
        case "RUNTIME_ROOT_REQUIRED": return l("ui.integrated.031")
        default: return l("ui.integrated.017")
        }
    }
    private var phase: String {
        switch state.operationEvents.last(where: { $0["performance_status"] != nil })?["performance_status"]?.text {
        case "backing_up": return l("ui.integrated.032")
        case "applying": return l("ui.integrated.033")
        case "restoring": return l("ui.integrated.034")
        default: return l("ui.integrated.035")
        }
    }
    private var confirmation: Binding<Bool> { Binding(get: { !state.performancePreview.isEmpty }, set: { if !$0 { state.discardPerformancePreview() } }) }
    private var changed: Bool { keys.contains { GamePerformanceInferenceService.differs(current[$0], state.editedPerformance[$0]) == true } }
    private func integer(_ key: String, fallback: Int) -> Binding<Int> {
        Binding(get: { state.editedPerformance[key]?.integer ?? fallback }, set: { state.editedPerformance[key] = .number(Double($0)) })
    }
    private func flag(_ key: String) -> Binding<Bool> {
        Binding(get: { state.editedPerformance[key]?.boolean ?? false }, set: { state.editedPerformance[key] = .bool($0) })
    }
    private var plan: GamePerformanceInferenceService.Plan { GamePerformanceInferenceService().infer(snapshot) }
    private var reading: Bool { state.guiRecords["read_performance"]?.status == .running }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.134"))
            TacticalButton(title: state.t("ui.243"), symbol: "arrow.clockwise", primary: true,
                loading: reading, disabledReason: state.tasks.busy ? state.t("ui.224") : nil) { state.runOperation("read_performance") }
            if let record = state.guiRecords["read_performance"] {
                TacticalStatusBadge(text: record.status.title(state), tone: record.error == nil ? .neutral : .error)
                if let error = record.error { TacticalWarningBanner(text: error.message(state.chinese), isError: true) }
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
                DisclosureGroup(l("ui.integrated.007")) {
                    ForEach(keys, id: \.self) { key in TacticalInfoRow(title: label(key), value: GamePerformanceInferenceService.render(plan.reference[key])) }
                }
                if plan.kind == .experimental {
                    TacticalWarningBanner(text: state.t("ui.111"))
                }
                Text(state.t("ui.277"))
                    .font(TacticalTypography.caption)
            }
            TacticalPanel(number: "D", title: l("ui.integrated.001"), symbol: "slider.horizontal.3") {
                TacticalButton(title: l("ui.integrated.002"), symbol: "arrow.clockwise", disabledReason: state.tasks.busy ? l("ui.224") : nil) {
                    state.runOperation("performance_read")
                }
                if !configuration.isEmpty {
                    Stepper(value: integer("cpus", fallback: 8), in: (rules["cpu_min"]?.integer ?? 1)...max(1, rules["cpu_max"]?.integer ?? 1)) {
                        Text(label("cpus") + ": " + GamePerformanceInferenceService.render(state.editedPerformance["cpus"]))
                    }
                    Stepper(value: integer("memMiB", fallback: 8192), in: (rules["memory_min"]?.integer ?? 4096)...max(4096, rules["memory_max"]?.integer ?? 4096), step: 256) {
                        Text(label("memMiB") + ": " + GamePerformanceInferenceService.render(state.editedPerformance["memMiB"]) + " MiB")
                    }
                    Picker(label("vulkanDriver"), selection: Binding(get: { state.editedPerformance["vulkanDriver"]?.text ?? "" }, set: { state.editedPerformance["vulkanDriver"] = .string($0) })) {
                        ForEach((rules["drivers"]?.array ?? []).compactMap(\.text), id: \.self) { Text($0).tag($0) }
                    }
                    Toggle(label("metalHUD"), isOn: flag("metalHUD"))
                    Toggle(label("superResolution"), isOn: flag("superResolution")).disabled(true)
                    Text(l("ui.integrated.003"))
                    ForEach(keys, id: \.self) { key in
                        TacticalInfoRow(title: label(key), value: GamePerformanceInferenceService.render(current[key]) + " → " + GamePerformanceInferenceService.render(state.editedPerformance[key]))
                    }
                    Text(l("ui.integrated.004"))
                    Text(l("ui.integrated.005"))
                    Text(l("ui.integrated.006"))
                    DisclosureGroup(l("ui.integrated.007")) {
                        ForEach(keys, id: \.self) { key in Text(key + ": " + GamePerformanceInferenceService.render(current[key])).font(TacticalTypography.log) }
                        Text(verbatim: "es.fxgam.steamac · FX 1.9.4")
                        Text(verbatim: "CPU: 1–" + String(rules["cpu_max"]?.integer ?? 0))
                        Text(verbatim: "MiB: 4096–" + String(rules["memory_max"]?.integer ?? 0) + " / 256")
                    }
                }
                TacticalInfoRow(title: l("ui.integrated.008"), value: "6144 MiB")
            }
            TacticalPanel(number: "E", title: l("ui.021"), symbol: "arrow.uturn.backward") {
                Text(l("ui.integrated.009"))
                TacticalWarningBanner(text: l("ui.integrated.010"))
                TacticalWarningBanner(text: l("ui.integrated.011"))
                Text(l("ui.integrated.036"))
                Text(l("ui.integrated.012"))
                Text(changed ? l("ui.integrated.013") : l("ui.integrated.014"))
                if let status = configuration["status"]?.text {
                    Text(status == "restored" ? l("ui.integrated.015") : l("ui.integrated.016"))
                }
                if let record = state.guiRecords.values.filter({ $0.method.hasPrefix("performance_") }).max(by: { $0.startedAt < $1.startedAt }) {
                    if record.status == .running { ProgressView(phase) }
                    if let error = record.error {
                        TacticalWarningBanner(text: failureMessage(error.code), isError: true)
                        DisclosureGroup(l("ui.integrated.018")) { Text(error.code).font(TacticalTypography.log) }
                    }
                }
                HStack {
                    TacticalButton(title: l("ui.integrated.019"), symbol: "checkmark", disabledReason: configuration.isEmpty || !changed || state.tasks.busy ? l("ui.integrated.020") : nil) { state.previewPerformance() }
                    TacticalButton(title: l("ui.integrated.021"), symbol: "arrow.uturn.backward", disabledReason: configuration["can_restore"]?.boolean != true || state.tasks.busy ? l("ui.integrated.022") : nil) { state.previewPerformance(restore: true) }
                }
            }
        }
        .sheet(isPresented: confirmation) {
            VStack(alignment: .leading, spacing: 16) {
                Text(l("ui.integrated.023")).font(.title2)
                ForEach(keys, id: \.self) { key in
                    if let change = state.performancePreview["changes"]?.object[key]?.object {
                        Text(label(key) + ": " + GamePerformanceInferenceService.render(change["before"]) + " → " + GamePerformanceInferenceService.render(change["after"]))
                    }
                }
                Text(l("ui.integrated.024"))
                Text(l("ui.integrated.011"))
                Text(l("ui.integrated.036"))
                HStack {
                    Button(l("ui.037")) { state.discardPerformancePreview() }
                    Button(l("ui.integrated.025")) { state.confirmPerformance() }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 560)
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
}
