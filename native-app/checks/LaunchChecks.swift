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
        print("7 launch state checks PASS")
    }
}
