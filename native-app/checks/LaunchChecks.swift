import Foundation

@main struct LaunchChecks {
    static func main() throws {
        func check(_ value: Bool, _ message: String) throws {
            guard value else { throw ErrorState("ASSERTION_FAILED", method: message) }
            print("PASS " + message)
        }
        var session = LaunchSession(); session.begin(root: "fixture")
        session.confirmMainMenu(); session.confirmSinglePlayer()
        try check(session.mainMenuConfirmedAt == nil && session.singlePlayerConfirmedAt == nil, "confirmation requires observed process and completed operation")
        session.consume(["stage":.string("StartingSteam"), "status":.string("done"), "sequence":.number(5)])
        session.consume(["stage":.string("StartingFX"), "status":.string("done"), "sequence":.number(2)])
        try check(session.current == .startingSteam && session.evidence[.startingFX] == "done", "out-of-order progress preserves stage evidence without moving current stage backwards")
        session.complete(["game_process_detected":.bool(true)], at:"fixture")
        try check(session.processDetected && session.mainMenuConfirmedAt == nil && session.singlePlayerConfirmedAt == nil, "process success never infers gameplay")
        session.confirmSinglePlayer()
        try check(session.singlePlayerConfirmedAt == nil, "single-player confirmation requires main menu first")
        session.confirmMainMenu(); session.confirmSinglePlayer()
        try check(session.mainMenuConfirmedAt != nil && session.singlePlayerConfirmedAt != nil, "explicit user confirmations are recorded separately")
        session.begin(root:"new attempt")
        try check(!session.processDetected && session.mainMenuConfirmedAt == nil, "new attempt clears prior gameplay evidence")
        session.complete(["game_process_detected":.bool(true)], at:"fixture")
        session.fail(ErrorState("GAME_EXITED", details:["stage":.string("GameProcessDetected")]))
        session.consume(["stage":.string("GameProcessDetected"),"status":.string("done"),"sequence":.number(99)])
        try check(!session.processDetected && session.current == .failed, "late progress cannot revive a process after final exit")
        session.begin(root: "fixture")
        session.consume(["kind": .string("launch_context"), "fx_path": .string("fixture.app"), "fx_version": .string("1.9.4")])
        let initial = session.diagnostic(appVersion: "fixture-version")
        try check(initial["fx_path"]?.text == "fixture.app" && initial["started_at"]?.text != nil && initial["app_version"]?.text == "fixture-version", "diagnostics bind actual target and start/version metadata")
        session.complete(["game_process_detected": .bool(true)], at: "fixture")
        try check(session.diagnostic(appVersion: "fixture")["main_menu"]?.text == "unverified" && session.diagnostic(appVersion: "fixture")["game_window"]?.text == "unverified", "process detection never records window or menu success")
        session.confirmMainMenu()
        try check(session.diagnostic(appVersion: "fixture")["main_menu"]?.text == "user_confirmed", "diagnostics record explicit menu confirmation")
        session.begin(root: "fixture")
        session.fail(ErrorState("SUDO_AUTH_FAILED", details: ["stage": .string("CheckingCompatibility")]))
        let failure = session.diagnostic(appVersion: "fixture")
        try check(failure["error_code"]?.text == "SUDO_AUTH_FAILED" && !(failure["error_summary"]?.text ?? "").isEmpty && failure["main_menu"]?.text == "unverified", "sudo refusal has an actionable summary without menu success")
        try check(!GUIAction.connect.accepts(["fx_host_running":.bool(true)]) && !GUIAction.connect.accepts(["ssh_connected":.bool(false), "guest_ready":.bool(true)]), "host existence and negative SSH are never connected")
        try check(GUIAction.connect.accepts(["ssh_connected":.bool(true),"guest_ready":.bool(true)]) && !GUIAction.inspect.accepts(["ssh_connected":.bool(true),"guest_ready":.bool(true),"guest_os":.string("Linux"),"components":.array([])]), "connection needs identity and inspection needs typed component evidence")
        try check(GUIAction.fxState.accepts(["fx_host_running":.bool(false)]) && !GUIAction.startFX.accepts(["fx_host_running":.bool(false)]) && !GUIAction.steam.accepts(["ssh_connected":.bool(true),"steam_running":.bool(false)]), "successful status query can report stopped without start success")
        for (code, expected) in [("CANCELLED", GUIOperationStatus.cancelled),("TIMEOUT",.timedOut),("SSH_AUTH_FAILED",.failed)] {
            var record=GUIOperationRecord(method:"connect_fx",target:"fixture")
            record.finish(ErrorState(code))
            try check(record.status == expected && record.endedAt! >= record.startedAt, "terminal action status and actual timing: " + code)
        }
        print("17 launch and GUI state checks PASS")
    }
}
