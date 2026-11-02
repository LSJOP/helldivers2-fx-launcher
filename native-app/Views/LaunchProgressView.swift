import SwiftUI

struct LaunchProgressView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    var body: some View {
        TacticalPanel(number: "L", title: state.t("本次启动进度", "Current launch progress"), symbol: "play.rectangle") {
            Text(state.launchSession.current.title(state.chinese)).font(TacticalTypography.module)
            ForEach([LaunchStage.checkingEnvironment, .startingFX, .waitingForGuest, .checkingCompatibility, .startingSteam, .gameProcessDetected, .checkingEAC]) { stage in
                let value = state.launchSession.evidence[stage] ?? "unverified"
                HStack {
                    Image(systemName: value == "done" || value == "passed" ? "checkmark.circle" : value == "failed" ? "exclamationmark.circle" : "circle.dashed")
                    Text(stage.title(state.chinese))
                    Spacer()
                    Text(value == "done" || value == "passed" ? state.t("本次已观察", "Observed this attempt") : value == "running" ? state.t("进行中", "In progress") : value == "failed" ? state.t("失败", "Failed") : state.t("未验证", "Unverified"))
                }.font(TacticalTypography.caption)
            }
            if let failure = state.launchSession.failure {
                let stage = failure.details["stage"]?.text.flatMap(LaunchStage.init(rawValue:))
                TacticalWarningBanner(text: (stage?.title(state.chinese) ?? state.t("启动", "Launch")) + " · " + failure.message(state.chinese) + " [" + failure.code + "]", isError: true)
                if let detail = failure.details["summary"]?.text { Text(detail).font(TacticalTypography.log).textSelection(.enabled) }
            }
            TacticalInfoRow(title: state.t("进入主菜单", "Main menu"), value: state.launchSession.mainMenuConfirmedAt.map { state.t("用户确认 · ", "User confirmed · ") + $0 } ?? state.t("待用户确认", "Awaiting user confirmation"))
            TacticalInfoRow(title: state.t("进入单人任务", "Single-player mission"), value: state.launchSession.singlePlayerConfirmedAt.map { state.t("用户确认 · ", "User confirmed · ") + $0 } ?? state.t("待用户确认", "Awaiting user confirmation"))
            Text(state.t("进程证据是最近一次读数，不代表已进入主菜单。仅在亲自看到相应游戏画面后确认。EAC 独立显示，多人匹配不在本阶段验收范围。", "Process evidence is a last observation, not proof of the main menu. Confirm only after seeing the corresponding game screen. EAC is separate; multiplayer is outside this phase."))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            Button(state.t("我已进入主菜单", "I reached the main menu")) { state.confirmMainMenu() }
                .disabled(tasks.busy || !state.launchSession.processDetected || state.launchSession.mainMenuConfirmedAt != nil)
            Button(state.t("我已进入单人任务", "I entered a single-player mission")) { state.confirmSinglePlayer() }
                .disabled(tasks.busy || !state.launchSession.processDetected || state.launchSession.mainMenuConfirmedAt == nil || state.launchSession.singlePlayerConfirmedAt != nil)
            Button(state.t("只读复查游戏进程", "Recheck game process (read-only)")) { state.runOperation("observe_launch", params: ["confirmed": .bool(true)]) }
                .disabled(tasks.busy || state.runtimeRoot.isEmpty)
        }
    }
}
