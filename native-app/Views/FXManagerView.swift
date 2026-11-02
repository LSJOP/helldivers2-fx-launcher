import SwiftUI

struct FXManagerView: View {
    @ObservedObject var state: AppState
    var body: some View {
        Text(state.t("仅读取 /Applications 与 ~/Applications 的浅层 FX 元数据；不会选择或切换运行版本。", "Reads shallow FX metadata in /Applications and ~/Applications. Runtime selection and switching are disabled."))
            .foregroundStyle(.secondary)
        if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
            Label(state.t("扫描不完整：达到数量限制或无法读取目录。", "Partial scan: a directory limit or read error was encountered."), systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        }
        let candidates = state.rows("list_fx_versions", "candidates")
        if candidates.isEmpty {
            ContentUnavailableView(state.t("没有可显示的 FX 候选", "No FX candidates to display"), systemImage: "shippingbox",
                description: Text(state.t("尚未读取或限定范围内未找到；不代表本机没有安装。", "Not inspected yet, or none found in the bounded scope. This does not establish absence elsewhere.")))
        }
        ForEach(Array(candidates.enumerated()), id: \.offset) { index, row in
            GroupBox("FX \(index + 1)") {
                VStack {
                    FactRow(title: state.t("版本", "Version"), value: row["version"]?.text ?? state.t("未知", "Unknown"))
                    FactRow(title: state.t("位置范围", "Location scope"), value: row["location"]?.text ?? "Unknown")
                    FactRow(title: state.t("结构元数据", "Bundle metadata"), value: row["structure"]?.text == "metadata_valid" ? state.t("匹配 Core 结构规则", "Matches Core structure rules") : state.t("未验证", "Unverified"))
                    FactRow(title: state.t("启动 / EAC / 联机", "Launch / EAC / Multiplayer"), value: state.t("均未验证", "All unverified"))
                }.padding(8)
            }
        }
    }
}
