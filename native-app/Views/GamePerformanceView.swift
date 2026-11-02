import SwiftUI

struct GamePerformanceView: View {
    @ObservedObject var state: AppState
    private let keys = ["cpus", "memMiB", "vulkanDriver", "metalHUD", "superResolution"]
    private var snapshot: [String: JSONValue] { state.performanceSnapshot }
    private var hardware: [String: JSONValue] { snapshot["hardware"]?.object ?? [:] }
    private var configuration: [String: JSONValue] { state.performanceConfiguration }
    private var rules: [String: JSONValue] { configuration["capabilities"]?.object ?? [:] }
    private var current: [String: JSONValue] { configuration["current"]?.object ?? snapshot["current"]?.object ?? [:] }
    private func l(_ text: String) -> String { NativeLocalization.localized(text, language: state.languageCode) }
    private func failureMessage(_ code: String) -> String {
        switch code {
        case "PERF_RUNNING": return l("FX is running. Stop FX yourself before saving.")
        case "PERF_CONFLICT": return l("Configuration changed externally. Reload before continuing.")
        case "PERF_VERSION": return l("This FX version or build is not supported for editing.")
        case "PERF_BACKUP": return l("The backup is unavailable or invalid. No restore was performed.")
        case "PERF_RANGE", "PERF_PARAMETER": return l("A parameter is unsupported or outside the allowed range.")
        case "RUNTIME_ROOT_REQUIRED": return l("Select an existing launcher directory in FX Manager first.")
        default: return l("Configuration operation failed. Reload the configuration and check FX is stopped.")
        }
    }
    private var phase: String {
        switch state.operationEvents.last(where: { $0["performance_status"] != nil })?["performance_status"]?.text {
        case "backing_up": return l("Creating verified backup")
        case "applying": return l("Applying configuration")
        case "restoring": return l("Restoring configuration")
        default: return l("Checking configuration")
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
            TacticalPageHeader(title: state.t("游戏性能配置", "Game Performance"))
            TacticalButton(title: state.t("读取硬件与当前配置", "Read hardware and configuration"), symbol: "arrow.clockwise", primary: true,
                loading: reading, disabledReason: state.tasks.busy ? state.t("操作执行中", "Operation in progress") : nil) { state.runOperation("read_performance") }
            if let record = state.guiRecords["read_performance"] {
                TacticalStatusBadge(text: record.status.title(state), tone: record.error == nil ? .neutral : .error)
                if let error = record.error { TacticalWarningBanner(text: error.message(state.chinese), isError: true) }
            }
            TacticalPanel(number: "A", title: state.t("当前硬件", "Current hardware"), symbol: "cpu") {
                TacticalAdaptiveLayout(minimumWidth: 155, maximumColumns: 2) {
                    TacticalMetric(title: state.t("芯片", "Chip"), value: hardware["chip"]?.text ?? unknown, symbol: "cpu")
                    TacticalMetric(title: state.t("CPU 核心", "CPU cores"), value: number("cpu_cores"), symbol: "cpu")
                    TacticalMetric(title: state.t("GPU 核心", "GPU cores"), value: number("gpu_cores"), symbol: "square.stack.3d.up")
                    TacticalMetric(title: state.t("统一内存", "Unified memory"), value: memory, symbol: "memorychip")
                }
                TacticalInfoRow(title: "macOS", value: hardware["os_version"]?.text ?? unknown)
                Text(state.t("只读探测本机。GPU 无明确结果时保持未知，不采用芯片系列最大规格。", "Read-only host detection. Unknown GPU counts remain unknown; model maxima are never substituted."))
                    .font(TacticalTypography.caption).foregroundStyle(.secondary)
            }
            TacticalPanel(number: "B", title: state.t("当前配置", "Current configuration"), symbol: "slider.horizontal.3") {
                Text(state.t("读取 FX 偏好设置，不代表正在运行的 Guest 已生效。", "Reads FX preferences; these do not prove the running Guest uses them."))
                ForEach(keys, id: \.self) { key in TacticalInfoRow(title: label(key), value: GamePerformanceInferenceService.render(current[key])) }
                if !(snapshot["read_errors"]?.array.isEmpty ?? true) { TacticalWarningBanner(text: state.t("部分偏好读取失败；缺失值不会当作默认值。", "Some preferences could not be read; missing values are not treated as defaults.")) }
            }
            TacticalPanel(number: "C", title: state.t("推荐配置", "Recommendation"), symbol: "lightbulb") {
                TacticalStatusBadge(text: plan.kind == .localBaseline ? state.t("本机基准配置 · 候选", "Local baseline · Candidate") : state.t("暂无适配配置", "No suitable profile"), tone: .warning)
                Text(state.t("候选基准为 M4 Pro／24 GiB 的原脚本记录，并非全面性能验收。其他芯片或内存规格没有可靠推算边界，暂不生成可写推荐。", "The candidate comes from the recorded M4 Pro / 24 GiB script settings, not comprehensive performance testing. No validated inference bounds exist for other chips or memory tiers; no writable recommendation is generated."))
                DisclosureGroup(l("Advanced details")) {
                    ForEach(keys, id: \.self) { key in TacticalInfoRow(title: label(key), value: GamePerformanceInferenceService.render(plan.reference[key])) }
                }
                if plan.kind == .experimental {
                    TacticalWarningBanner(text: state.t("实验性配置：此配置根据已有 M4 Pro 基准配置及当前设备硬件信息推算生成，尚未在当前芯片上完成实际测试。性能、稳定性和兼容性可能存在差异。", "Experimental profile: inferred from the existing M4 Pro baseline and current hardware. It has not been tested on this chip; performance, stability and compatibility may differ."))
                }
                Text(state.t("规则：仅芯片与内存精确匹配时标记本机候选；不按 GPU 倍数缩放，不推算 EAC、权限、连接地址或游戏路径。", "Rule: exact chip and memory matches yield a local candidate only. No GPU-ratio scaling or inference of EAC, permissions, connection addresses or game paths."))
                    .font(TacticalTypography.caption)
            }
            TacticalPanel(number: "D", title: l("Edit parameters"), symbol: "slider.horizontal.3") {
                TacticalButton(title: l("Read editable configuration"), symbol: "arrow.clockwise", disabledReason: state.tasks.busy ? l("Operation in progress") : nil) {
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
                    Text(l("Super resolution is read-only until MetalFX device support is verified."))
                    ForEach(keys, id: \.self) { key in
                        TacticalInfoRow(title: label(key), value: GamePerformanceInferenceService.render(current[key]) + " → " + GamePerformanceInferenceService.render(state.editedPerformance[key]))
                    }
                    Text(l("CPU and memory share host resources. Native limits reserve memory for macOS and the GPU."))
                    Text(l("Changing Vulkan drivers may rebuild shader caches and affect compatibility."))
                    Text(l("Metal HUD displays performance counters; it does not improve game performance."))
                    DisclosureGroup(l("Advanced details")) {
                        ForEach(keys, id: \.self) { key in Text(key + ": " + GamePerformanceInferenceService.render(current[key])).font(TacticalTypography.log) }
                        Text("es.fxgam.steamac · FX 1.9.4")
                        Text("CPU: 1–" + String(rules["cpu_max"]?.integer ?? 0))
                        Text("MiB: 4096–" + String(rules["memory_max"]?.integer ?? 0) + " / 256")
                    }
                }
                TacticalInfoRow(title: l("GPU memory budget (read-only)"), value: "6144 MiB")
            }
            TacticalPanel(number: "E", title: l("Apply and restore"), symbol: "arrow.uturn.backward") {
                Text(l("Running configuration unverified"))
                TacticalWarningBanner(text: l("Save while FX is stopped. Restart FX and Guest to load saved settings. No automatic restart."))
                TacticalWarningBanner(text: l("The original launch command overrides CPU, memory and Vulkan settings. Saved values are not guaranteed to be used."))
                Text(l("Custom values may be rejected by the original game launch preflight. Restore the backup before using that launch path."))
                Text(l("No verified performance recommendation is available."))
                Text(changed ? l("Unsaved changes") : l("Unmodified"))
                if let status = configuration["status"]?.text {
                    Text(status == "restored" ? l("Restored; runtime adoption unverified") : l("Saved; runtime adoption unverified"))
                }
                if let record = state.guiRecords.values.filter({ $0.method.hasPrefix("performance_") }).max(by: { $0.startedAt < $1.startedAt }) {
                    if record.status == .running { ProgressView(phase) }
                    if let error = record.error {
                        TacticalWarningBanner(text: failureMessage(error.code), isError: true)
                        DisclosureGroup(l("View details")) { Text(error.code).font(TacticalTypography.log) }
                    }
                }
                HStack {
                    TacticalButton(title: l("Preview changes"), symbol: "checkmark", disabledReason: configuration.isEmpty || !changed || state.tasks.busy ? l("Read the configuration and edit parameters first") : nil) { state.previewPerformance() }
                    TacticalButton(title: l("Restore last configuration"), symbol: "arrow.uturn.backward", disabledReason: configuration["can_restore"]?.boolean != true || state.tasks.busy ? l("No valid backup or configuration has changed") : nil) { state.previewPerformance(restore: true) }
                }
            }
        }
        .sheet(isPresented: confirmation) {
            VStack(alignment: .leading, spacing: 16) {
                Text(l("Confirm configuration changes")).font(.title2)
                ForEach(keys, id: \.self) { key in
                    if let change = state.performancePreview["changes"]?.object[key]?.object {
                        Text(label(key) + ": " + GamePerformanceInferenceService.render(change["before"]) + " → " + GamePerformanceInferenceService.render(change["after"]))
                    }
                }
                Text(l("A verified backup is required before writing. External changes stop the operation."))
                Text(l("The original launch command overrides CPU, memory and Vulkan settings. Saved values are not guaranteed to be used."))
                Text(l("Custom values may be rejected by the original game launch preflight. Restore the backup before using that launch path."))
                HStack {
                    Button(l("Cancel")) { state.discardPerformancePreview() }
                    Button(l("Confirm and save")) { state.confirmPerformance() }.keyboardShortcut(.defaultAction)
                }
            }.padding(24).frame(width: 560)
        }
        .task { if snapshot.isEmpty && !state.tasks.busy { state.runOperation("read_performance") } }
    }
    private var unknown: String { state.t("未知／尚未读取", "Unknown / Not read") }
    private func number(_ key: String) -> String { hardware[key]?.integer.map(String.init) ?? unknown }
    private var memory: String { guard let bytes = hardware["memory_bytes"]?.integer else { return unknown }; return String(format: "%g GiB", Double(bytes) / pow(1024, 3)) }
    private func difference(_ key: String) -> String {
        guard let differs = GamePerformanceInferenceService.differs(current[key], plan.reference[key]) else { return state.t("无法比较", "Cannot compare") }
        return differs ? state.t("不同", "Different") : state.t("相同", "Same")
    }
    private func label(_ key: String) -> String {
        switch key {
        case "cpus": return state.t("虚拟 CPU 数量", "Virtual CPU count")
        case "memMiB": return state.t("Guest 内存（MiB）", "Guest memory (MiB)")
        case "vulkanDriver": return state.t("Vulkan 驱动", "Vulkan driver")
        case "metalHUD": return state.t("性能监控叠层", "Performance overlay")
        default: return state.t("超分辨率", "Super resolution")
        }
    }
}
