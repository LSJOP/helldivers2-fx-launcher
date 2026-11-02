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
                if plan.kind == .experimental {
                    TacticalWarningBanner(text: state.t("实验性配置：此配置根据已有 M4 Pro 基准配置及当前设备硬件信息推算生成，尚未在当前芯片上完成实际测试。性能、稳定性和兼容性可能存在差异。", "Experimental profile: inferred from the existing M4 Pro baseline and current hardware. It has not been tested on this chip; performance, stability and compatibility may differ."))
                }
                Text(state.t("规则：仅芯片与内存精确匹配时标记本机候选；不按 GPU 倍数缩放，不推算 EAC、权限、连接地址或游戏路径。", "Rule: exact chip and memory matches yield a local candidate only. No GPU-ratio scaling or inference of EAC, permissions, connection addresses or game paths."))
                    .font(TacticalTypography.caption)
            }
            TacticalPanel(number: "D", title: state.t("参数差异与来源", "Differences and sources"), symbol: "list.bullet.rectangle") {
                ForEach(keys, id: \.self) { key in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(label(key)).font(TacticalTypography.body.weight(.semibold))
                            Spacer()
                            Text(difference(key)).font(TacticalTypography.caption)
                        }
                        TacticalInfoRow(title: state.t("当前 → 记录基准", "Current → Recorded baseline"), value: GamePerformanceInferenceService.render(current[key]) + " → " + GamePerformanceInferenceService.render(plan.reference[key]))
                        Text(parameterNote(key)).font(TacticalTypography.caption).foregroundStyle(.secondary)
                        Text("performance_profile.SETTINGS · " + key).font(TacticalTypography.log).foregroundStyle(.secondary)
                        TacticalDivider()
                    }
                }
                Text(state.t("原启动入口的 GPU 内存预算为 6144 MiB；这是固定启动组合的记录，不是当前 Guest 实测值，也不随硬件自动推算。", "The recorded entry uses a 6144 MiB GPU budget. This belongs to the fixed launch combination, is not an observation of the current Guest, and is not scaled automatically."))
                    .font(TacticalTypography.caption)
            }
            TacticalPanel(number: "E", title: state.t("应用与恢复", "Apply and restore"), symbol: "arrow.uturn.backward") {
                TacticalWarningBanner(text: state.t("本页只读：尚无可靠跨硬件推算范围和仅恢复已改参数的后端，因此不会创建、应用或恢复配置。原有成功环境保持不变。", "Read-only: validated inference bounds and a restore backend limited to changed parameters are unavailable. This page does not create, apply or restore settings. The successful environment is preserved."))
                HStack {
                    TacticalButton(title: state.t("应用配置", "Apply profile"), symbol: "checkmark", disabledReason: state.t("尚无安全写入方案", "No safe write plan")) {}
                    TacticalButton(title: state.t("恢复上次配置", "Restore last profile"), symbol: "arrow.uturn.backward", disabledReason: state.t("尚无限定参数恢复后端", "No scoped restore backend")) {}
                }
            }
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
    private func parameterNote(_ key: String) -> String {
        if ["cpus", "memMiB"].contains(key) {
            return state.t("性能参数；本机候选固定值。跨设备安全范围未建立，禁止自动推算。生效需要 Guest 重启，本页不执行。", "Performance parameter; fixed local candidate. Cross-device safe bounds are not established, so inference is disabled. Requires Guest restart to take effect; this page does not restart it.")
        }
        return state.t("固定兼容／显示参数；可能影响兼容性，不自动推算。更改后可能需要 Guest 重启，本页不修改。", "Fixed compatibility/display parameter; may affect compatibility and is not inferred. A Guest restart may be needed after a change; this page makes no changes.")
    }
}
