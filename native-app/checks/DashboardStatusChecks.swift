import Foundation

@main struct DashboardStatusChecks {
    static func main() throws {
        var count = 0
        let cards: [(String, LaunchStage?)] = [("fx_host_running", .startingFX), ("ssh_connected", .waitingForGuest), ("steam_running", .startingSteam), ("eac", .checkingEAC), ("multiplayer", nil)]
        func check(_ actual: DashboardStatus, _ tone: DashboardStatus.Tone, _ label: String, _ name: String) throws {
            guard actual.tone == tone && actual.textKey == label else { throw ErrorState("ASSERTION_FAILED", method: name) }
            count += 1; print("PASS \(name)")
        }
        for (key, stage) in cards {
            func status(_ evidence: [String: JSONValue] = [:], stale: Bool = false, session: LaunchSession = LaunchSession(), workflow: EnvironmentWorkflow = EnvironmentWorkflow()) -> DashboardStatus {
                DashboardStatus.resolve(key: key, stage: stage, session: session, workflow: workflow, evidence: evidence, stale: stale)
            }
            try check(status(), .unknown, "ui.368", "\(key): absent evidence is gray")
            try check(status([key: .bool(false)]), .unknown, "ui.368", "\(key): negative query does not invent failure")
            try check(status([key: .string("true")]), .unknown, "ui.368", "\(key): untyped evidence rejected")
            let positive: [String: JSONValue] = [key: .bool(true), "guest_ready": .bool(true)]
            let supported = ["fx_host_running", "ssh_connected", "steam_running"].contains(key)
            let label = key == "ssh_connected" ? "ui.dashboard.connected" : "ui.dashboard.process"
            try check(status(positive), supported ? .success : .unknown, supported ? label : "ui.368", "\(key): green only for directly supported scope")
            try check(status(positive, stale: true), .unknown, "ui.368", "\(key): stale positive is gray")
            var session = LaunchSession(); session.begin(root: "fixture")
            if let stage {
                session.current = stage
                try check(status(positive, session: session), .working, "ui.157", "\(key): active check is yellow")
                session.running = false; session.evidence[stage] = "failed"
                try check(status(positive, session: session), .failed, "ui.125", "\(key): failed stage is red despite older success")
                try check(status(positive, stale: true, session: session), .unknown, "ui.368", "\(key): stale failure is gray")
                session.evidence[stage] = "done"
                try check(status(session: session), .unknown, "ui.368", "\(key): stage completion alone is gray")
            }
        }
        func resolve(_ key: String, _ evidence: [String: JSONValue], _ workflow: EnvironmentWorkflow = EnvironmentWorkflow()) -> DashboardStatus {
            DashboardStatus.resolve(key: key, stage: nil, session: LaunchSession(), workflow: workflow, evidence: evidence, stale: false)
        }
        try check(resolve("ssh_connected", ["ssh_connected": .bool(true)]), .unknown, "ui.368", "SSH without verified Guest is gray")
        try check(resolve("ssh_connected", ["ssh_connected": .bool(true), "guest_ready": .bool(false)]), .unknown, "ui.368", "Guest refusal overrides SSH presence")
        try check(resolve("steam_running", ["steam_process_count": .number(1)]), .success, "ui.dashboard.process", "Steam count proves only observed process")
        try check(resolve("steam_running", ["steam_process_count": .number(0)]), .unknown, "ui.368", "Zero Steam count is gray")
        for phase in [EnvironmentWorkflowPhase.startingFX, .connecting] {
            var workflow = EnvironmentWorkflow(); workflow.phase = phase
            try check(resolve(phase == .startingFX ? "fx_host_running" : "ssh_connected", [:], workflow), .working, "ui.157", "Workflow \(phase) is yellow")
        }
        for stage in [LaunchStage.checkingFXEntry, .waitingForFXReady, .verifyingFXIdentity] {
            var session = LaunchSession(); session.begin(root: "fixture"); session.current = stage
            try check(DashboardStatus.resolve(key: "fx_host_running", stage: .startingFX, session: session, workflow: EnvironmentWorkflow(), evidence: [:], stale: false), .working, "ui.157", "FX \(stage) is yellow")
            session.running = false; session.evidence[stage] = "failed"
            try check(DashboardStatus.resolve(key: "fx_host_running", stage: .startingFX, session: session, workflow: EnvironmentWorkflow(), evidence: [:], stale: false), .failed, "ui.125", "FX \(stage) failure is red")
        }
        var completed = LaunchSession(); completed.complete(["game_process_detected": .bool(true)], at: "fixture"); completed.confirmMainMenu(); completed.confirmSinglePlayer()
        for key in ["eac", "multiplayer"] {
            try check(DashboardStatus.resolve(key: key, stage: key == "eac" ? .checkingEAC : nil, session: completed, workflow: EnvironmentWorkflow(), evidence: ["game_process_detected": .bool(true), "eac": .bool(true), "multiplayer": .bool(true)], stale: false), .unknown, "ui.368", "\(key): process/menu/single-player/generic flags cannot establish success")
        }
        print("PASS \(count) dashboard state matrix assertions (isolated; no live FX/game acceptance)")
    }
}
