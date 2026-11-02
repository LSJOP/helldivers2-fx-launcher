import SwiftUI

struct EnvironmentView: View {
    @ObservedObject var state: AppState
    private var unknown: String { state.t("未验证", "Unverified") }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(number: "02", title: state.t("运行环境检测", "Environment inspection"), section: Page.environment.title(state.chinese))
            TacticalAdaptiveLayout(minimumWidth: 140, maximumColumns: 4) {
                TacticalMetric(title: "macOS", value: state.value("get_system_info", "os_version"), symbol: "apple.logo")
                TacticalMetric(title: state.t("架构", "Architecture"), value: state.value("get_system_info", "arch"), symbol: "cpu")
                TacticalMetric(title: "Python", value: state.value("get_system_info", "python"), symbol: "terminal")
                TacticalMetric(title: state.t("依赖状态", "Dependencies"), value: unknown, symbol: "square.stack.3d.up")
            }
            TacticalAdaptiveLayout(minimumWidth: 255, maximumColumns: 2) {
                TacticalPanel(number: "A", title: state.t("本地依赖", "Local dependencies"), symbol: "shippingbox") {
                    ForEach(state.rows("get_dependencies", "items"), id: \.selfName) { row in
                        TacticalInfoRow(title: TacticalEvidence.name(row["name"]?.text ?? "—", state), value: TacticalEvidence.dependency(row["state"]?.text ?? "unknown", state))
                    }
                    if state.rows("get_dependencies", "items").isEmpty { Text(state.t("尚未读取", "Not yet inspected")) }
                }
                TacticalPanel(number: "B", title: state.t("运行组件", "Runtime components"), symbol: "cpu") {
                    TacticalInfoRow(title: state.t("FX 运行时", "FX runtime"), value: unknown)
                    TacticalInfoRow(title: state.t("gvproxy 运行时", "gvproxy runtime"), value: unknown)
                    TacticalWarningBanner(text: state.t("文件存在不代表运行就绪；本阶段不连接 Guest。", "File presence does not establish runtime readiness. This phase does not connect to Guest."))
                }
            }
            TacticalPanel(number: "C", title: state.t("游戏运行链路 · 检测范围", "Game runtime chain · inspection scope"), symbol: "point.3.connected.trianglepath.dotted") {
                TacticalAdaptiveLayout(minimumWidth: 95, maximumColumns: 6) {
                    ForEach(["FX", "SSH", "Guest", "Steam", "EAC", "Multiplayer"], id: \.self) { name in
                        VStack(spacing: 10) {
                            Image(systemName: name == "EAC" ? "shield.lefthalf.filled" : "shippingbox").font(.title2)
                            Text(TacticalEvidence.name(name, state)).font(TacticalTypography.body.weight(.semibold))
                            TacticalStatusBadge(text: unknown)
                        }.frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
            }
        }
    }
}

// The bridge guarantees unique dependency names; use their semantic identity.
private extension Dictionary where Key == String, Value == JSONValue {
    var selfName: String { self["name"]?.text ?? "unknown" }
}
