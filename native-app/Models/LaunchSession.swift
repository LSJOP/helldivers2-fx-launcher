import Foundation

enum LaunchStage: String, CaseIterable, Identifiable {
    case idle = "Idle", checkingEnvironment = "CheckingEnvironment", startingFX = "StartingFX"
    case checkingFXEntry = "CheckingFXEntry"
    case waitingForFXReady = "WaitingForFXReady", verifyingFXIdentity = "VerifyingFXIdentity"
    case waitingForGuest = "WaitingForGuest", checkingCompatibility = "CheckingCompatibility"
    case startingSteam = "StartingSteam", launchingGame = "LaunchingGame", waitingForGame = "WaitingForGame"
    case gameProcessDetected = "GameProcessDetected", checkingEAC = "CheckingEAC", failed = "Failed"
    var id: String { rawValue }
    func title(_ zh: Bool) -> String { title(zh ? "zh-CN" : "en") }
    func title(_ language: String) -> String {
        switch self {
        case .idle: return NativeStrings.text("ui.156", language: language)
        case .checkingEnvironment: return NativeStrings.text("ui.057", language: language)
        case .startingFX: return NativeStrings.text("ui.120", language: language)
        case .checkingFXEntry: return NativeStrings.text("ui.121", language: language)
        case .waitingForFXReady: return NativeStrings.text("ui.fx.waitReady", language: language)
        case .verifyingFXIdentity: return NativeStrings.text("ui.fx.verifyIdentity", language: language)
        case .waitingForGuest: return NativeStrings.text("ui.384", language: language)
        case .checkingCompatibility: return NativeStrings.text("ui.054", language: language)
        case .startingSteam: return NativeStrings.text("ui.320", language: language)
        case .launchingGame: return NativeStrings.text("ui.269", language: language)
        case .waitingForGame: return NativeStrings.text("ui.385", language: language)
        case .gameProcessDetected: return NativeStrings.text("ui.140", language: language)
        case .checkingEAC: return NativeStrings.text("ui.303", language: language)
        case .failed: return NativeStrings.text("ui.179", language: language)
        }
    }
}

struct LaunchSession {
    var root = ""
    var startedAt: String?
    var fxPath: String?
    var fxVersion: String?
    var current: LaunchStage = .idle
    var evidence: [LaunchStage: String] = [:]
    var stageSequences: [LaunchStage: Int] = [:]
    var sequence = 0
    var running = false
    var failure: ErrorState?
    var observedAt: String?
    var mainMenuConfirmedAt: String?
    var singlePlayerConfirmedAt: String?
    var processDetected: Bool { evidence[.gameProcessDetected] == "done" || evidence[.gameProcessDetected] == "passed" }
    mutating func begin(root: String) { self = LaunchSession(); self.root = root; startedAt = ISO8601DateFormatter().string(from: Date()); current = .checkingEnvironment; running = true }
    mutating func consume(_ event: [String: JSONValue]) {
        guard running else { return }
        if event["kind"]?.text == "launch_context" {
            fxPath = event["fx_path"]?.text; fxVersion = event["fx_version"]?.text
        }
        guard let raw = event["stage"]?.text, let stage = LaunchStage(rawValue: raw),
              let order = event["sequence"]?.integer, order > (stageSequences[stage] ?? 0) else { return }
        stageSequences[stage] = order
        evidence[stage] = event["status"]?.text ?? "unverified"
        if running && order > sequence { sequence = order; current = stage }
    }
    mutating func complete(_ result: [String: JSONValue], at: String) {
        running = false; observedAt = at; failure = nil
        if result["game_process_detected"]?.boolean == true {
            evidence[.gameProcessDetected] = "done"; current = .gameProcessDetected
        } else if result["game_process_detected"]?.boolean == false {
            evidence[.gameProcessDetected] = "unverified"; current = .waitingForGame
            stageSequences[.gameProcessDetected] = Int.max
            mainMenuConfirmedAt = nil; singlePlayerConfirmedAt = nil
        }
    }
    mutating func fail(_ error: ErrorState) {
        running = false; failure = error; current = .failed
        if let raw = error.details["stage"]?.text, let stage = LaunchStage(rawValue: raw) { evidence[stage] = "failed" }
        // A failed or cancelled attempt cannot establish the current process state.
        // A later explicit observation can supply fresh evidence.
        evidence[.gameProcessDetected] = "unverified"; stageSequences[.gameProcessDetected] = Int.max
        mainMenuConfirmedAt = nil; singlePlayerConfirmedAt = nil
    }
    // A structured record, never evidence of a menu/window merely from process presence.
    func diagnostic(appVersion: String) -> [String: JSONValue] {
        ["started_at": .string(startedAt ?? "unknown"), "app_version": .string(appVersion),
         "runtime_root": .string(root), "fx_path": .string(fxPath ?? "unverified"),
         "fx_version": .string(fxVersion ?? "unverified"), "stage": .string(current.rawValue),
         "stages": .object(evidence.reduce(into: [:]) { $0[$1.key.rawValue] = .string($1.value) }),
         "error_code": .string(failure?.code ?? "none"),
         "error_summary": .string(failure?.details["summary"]?.text ?? failure?.message("en") ?? ""),
         "game_process_detected": .bool(processDetected), "game_window": .string("unverified"),
         "main_menu": .string(mainMenuConfirmedAt == nil ? "unverified" : "user_confirmed"),
         "main_menu_confirmed_at": .string(mainMenuConfirmedAt ?? "unverified")]
    }
    mutating func confirmMainMenu() {
        guard !running, processDetected else { return }
        mainMenuConfirmedAt = ISO8601DateFormatter().string(from: Date())
    }
    mutating func confirmSinglePlayer() {
        guard !running, processDetected, mainMenuConfirmedAt != nil else { return }
        singlePlayerConfirmedAt = ISO8601DateFormatter().string(from: Date())
    }
}


enum EnvironmentWorkflowDestination { case setup, game }

enum EnvironmentWorkflowPhase: String {
    case idle, startingFX, connecting, detecting, deploying, verifying, launching, completed, failed, cancelled
    var titleKey: String {
        switch self {
        case .idle: return "ui.workflow.idle"
        case .startingFX: return "ui.workflow.startingFX"
        case .connecting: return "ui.workflow.connecting"
        case .detecting: return "ui.workflow.detecting"
        case .deploying: return "ui.workflow.deploying"
        case .verifying: return "ui.workflow.verifying"
        case .launching: return "ui.workflow.launching"
        case .completed: return "ui.workflow.completed"
        case .failed: return "ui.workflow.failed"
        case .cancelled: return "ui.workflow.cancelled"
        }
    }
}
struct EnvironmentWorkflow {
    var phase: EnvironmentWorkflowPhase = .idle
    var completedSteps = 0
    var launchesGame = false
    var failure: ErrorState?
    var needsRestartApproval = false
    var deploymentStage: String?
    var evidence: [String: JSONValue] = [:]
    var totalSteps: Int { launchesGame ? 6 : 5 }
    var active: Bool { ![.idle, .completed, .failed, .cancelled].contains(phase) }
    var fraction: Double { phase == .completed ? 1 : min(Double(completedSteps) / Double(totalSteps), 0.99) }
}
