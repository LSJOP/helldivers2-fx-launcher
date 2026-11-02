import SwiftUI

struct EnvironmentView: View {
    @ObservedObject var state: AppState
    var body: some View {
        GroupBox(state.t("主机信息", "Host information")) {
            VStack {
                FactRow(title: "macOS", value: state.value("get_system_info", "os_version"))
                FactRow(title: state.t("架构", "Architecture"), value: state.value("get_system_info", "arch"))
                FactRow(title: "Python", value: state.value("get_system_info", "python"))
            }.padding(8)
        }
        GroupBox(state.t("本地依赖", "Local dependencies")) {
            VStack(alignment: .leading) {
                if state.rows("get_dependencies", "items").isEmpty { Text(state.t("尚未读取", "Not yet inspected")) }
                ForEach(Array(state.rows("get_dependencies", "items").enumerated()), id: \.offset) { _, row in
                    FactRow(title: row["name"]?.text ?? "Unknown", value: dependencyState(row["state"]?.text ?? "unknown"))
                }
                Text(state.t("文件存在仅说明已找到该文件；未执行 Node 或 SSH。", "File presence only; Node and SSH are never executed."))
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
        }
        GroupBox(state.t("运行环境", "Runtime environment")) {
            VStack {
                ForEach(Array(state.rows("get_environment_status", "checks").enumerated()), id: \.offset) { _, row in
                    FactRow(title: row["name"]?.text ?? "Unknown", value: state.t("未验证", "Unverified"))
                }
                if state.rows("get_environment_status", "checks").isEmpty { Text(state.t("尚未读取", "Not yet inspected")) }
            }.padding(8)
        }
    }
    private func dependencyState(_ value: String) -> String {
        switch value {
        case "running_bridge": return state.t("本次 Bridge 使用中", "Running this bridge")
        case "file_present_unverified": return state.t("找到文件 · 未验证", "File found · Unverified")
        case "missing": return state.t("限定路径未找到", "Not found in checked paths")
        case "invalid": return state.t("文件不可执行", "File is not executable")
        default: return state.t("未验证", "Unverified")
        }
    }
}
