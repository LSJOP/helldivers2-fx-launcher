import SwiftUI

struct LaunchProgressView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    var body: some View {
        TacticalPanel(number: "L", title: state.t("ui.088"), symbol: "play.rectangle") {
            Text(state.launchSession.current.title(state.languageCode)).font(TacticalTypography.module)
            ForEach([LaunchStage.checkingEnvironment, .checkingFXEntry, .startingFX, .waitingForGuest, .checkingCompatibility, .startingSteam, .gameProcessDetected, .checkingEAC]) { stage in
                let value = state.launchSession.evidence[stage] ?? "unverified"
                HStack {
                    Image(systemName: value == "done" || value == "passed" ? "checkmark.circle" : value == "failed" ? "exclamationmark.circle" : "circle.dashed")
                    Text(stage.title(state.languageCode))
                    Spacer()
                    Text(value == "done" || value == "passed" ? state.t("ui.220") : value == "running" ? state.t("ui.157") : value == "failed" ? state.t("ui.125") : state.t("ui.368"))
                }.font(TacticalTypography.caption)
            }
            if let failure = state.launchSession.failure {
                let stage = failure.details["stage"]?.text.flatMap(LaunchStage.init(rawValue:))
                TacticalWarningBanner(text: (stage?.title(state.languageCode) ?? state.t("ui.175")) + " · " + failure.message(state.languageCode) + " [" + failure.code + "]", isError: true)
                if let detail = failure.details["summary"]?.text { Text(detail).font(TacticalTypography.log).textSelection(.enabled) }
            }
            TacticalInfoRow(title: state.t("ui.188"), value: state.launchSession.mainMenuConfirmedAt.map { state.t("ui.376") + $0 } ?? state.t("ui.033"))
            TacticalInfoRow(title: state.t("ui.310"), value: state.launchSession.singlePlayerConfirmedAt.map { state.t("ui.376") + $0 } ?? state.t("ui.033"))
            Text(state.t("ui.236"))
                .font(TacticalTypography.caption).foregroundStyle(.secondary)
            Button(state.t("ui.155")) { state.confirmMainMenu() }
                .disabled(tasks.busy || !state.launchSession.processDetected || state.launchSession.mainMenuConfirmedAt != nil)
            Button(state.t("ui.154")) { state.confirmSinglePlayer() }
                .disabled(tasks.busy || !state.launchSession.processDetected || state.launchSession.mainMenuConfirmedAt == nil || state.launchSession.singlePlayerConfirmedAt != nil)
            Button(state.t("ui.259")) { state.runOperation("observe_launch", params: ["confirmed": .bool(true)]) }
                .disabled(tasks.busy || state.fxSelection.selected == nil)
        }
    }
}
