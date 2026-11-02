import SwiftUI

struct FXManagerView: View {
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("FX 版本管理", "FX version management"), refreshState: state)
            if state.results["list_fx_versions"]?["scan_incomplete"]?.boolean == true {
                TacticalWarningBanner(text: scanWarning + " " + state.t("这是扫描范围限制，不代表安装异常。", "This limits scan coverage; it does not indicate a damaged installation."))
            }
            let candidates = state.rows("list_fx_versions", "candidates")
            if candidates.isEmpty {
                TacticalWarningBanner(text: state.t("尚未读取或限定目录中未发现 FX；不代表本机没有安装。", "Not inspected yet, or no FX found in the bounded directories. This does not establish absence elsewhere."))
            }
            TacticalAdaptiveLayout(minimumWidth: 255, maximumColumns: 2) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, row in
                    TacticalPanel(number: String(format: "%02d", index + 1), title: "FX " + version(row), symbol: "shippingbox") {
                        TacticalStatusBadge(text: state.t("已发现 · 元数据", "Discovered · Metadata"))
                        TacticalInfoRow(title: state.t("App 名称", "App name"), value: row["path"]?.text.map { URL(fileURLWithPath: $0).lastPathComponent } ?? state.t("未知", "Unknown"))
                        TacticalInfoRow(title: state.t("扫描位置", "Discovery scope"), value: row["location"]?.text ?? state.t("未知", "Unknown"))
                        TacticalInfoRow(title: state.t("完整安装路径", "Full installation path"), value: row["path"]?.text ?? state.t("未知", "Unknown"))
                        TacticalDivider()
                        TacticalInfoRow(title: state.t("安装文件", "Installation files"), value: state.t("已发现 · 仅元数据", "Found · Metadata only"))
                        TacticalInfoRow(title: state.t("结构检测", "Structure check"), value: row["structure"]?.text == "metadata_valid" ? state.t("匹配 Core 结构规则", "Matches Core structure rules") : state.t("未验证", "Unverified"))
                        TacticalDivider()
                        TacticalInfoRow(title: state.t("进程 / 活动实例", "Process / Active instance"), value: state.t("无法确认 · 未执行实例关联检测", "Cannot confirm · No instance correlation probe"))
                        TacticalInfoRow(title: "Guest", value: state.t("无法确认 · 未检查连接", "Cannot confirm · Connection not checked"))
                        TacticalInfoRow(title: state.t("EAC / 联机", "EAC / Multiplayer"), value: state.t("均未验证", "All unverified"))
                    }
                }
            }
            LegacyOperationsView(state: state, scope: "fx")
            TacticalPanel(number: "i", title: state.t("检测说明", "Inspection notes"), symbol: "info.circle") {
                Text(state.t("仅读取 /Applications 与 ~/Applications 的浅层元数据，不识别活动实例、不选择或切换版本。结构匹配不表示运行就绪。", "Reads shallow metadata in /Applications and ~/Applications. Does not identify active instances, select or switch versions. Matching structure does not establish runtime readiness."))
                    .font(TacticalTypography.body)
            }
        }
    }
    private func version(_ row: [String: JSONValue]) -> String {
        let value = row["version"]?.text
        return value == nil || value == "unknown" ? state.t("未知", "Unknown") : value!
    }
    private var scanWarning: String {
        let issues = state.results["list_fx_versions"]?["issues"]?.array.compactMap(\.text) ?? []
        return issues.contains("DIRECTORY_UNAVAILABLE")
            ? state.t("扫描不完整：至少一个目录无法读取；每个目录最多检查 64 项。", "Partial scan: at least one directory could not be read; each directory is capped at 64 entries.")
            : state.t("扫描不完整：限定目录达到 64 项检查上限，部分应用可能未被检查。", "Partial scan: the 64-entry directory limit was reached; some apps may not have been inspected.")
    }
}
