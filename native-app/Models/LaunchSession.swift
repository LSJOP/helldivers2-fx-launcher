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
    private(set) var taskID: UUID?
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
    var launchCommandSucceeded: Bool?
    var observedAt: String?
    var mainMenuConfirmedAt: String?
    var singlePlayerConfirmedAt: String?
    var processDetected: Bool { evidence[.gameProcessDetected] == "done" || evidence[.gameProcessDetected] == "passed" }
    mutating func begin(root: String, taskID: UUID = UUID()) { self = LaunchSession(); self.taskID = taskID; self.root = root; startedAt = ISO8601DateFormatter().string(from: Date()); current = .checkingEnvironment; running = true }
    mutating func consume(_ event: [String: JSONValue]) {
        guard running else { return }
        if event["kind"]?.text == "launch_context" {
            fxPath = event["fx_path"]?.text; fxVersion = event["fx_version"]?.text
        }
        if event["kind"]?.text == "launch_request" { launchCommandSucceeded = event["command_succeeded"]?.boolean }
        guard let raw = event["stage"]?.text, let stage = LaunchStage(rawValue: raw),
              let order = event["sequence"]?.integer, order > (stageSequences[stage] ?? 0) else { return }
        stageSequences[stage] = order
        evidence[stage] = event["status"]?.text ?? "unverified"
        if running && order > sequence { sequence = order; current = stage }
    }
    mutating func complete(_ result: [String: JSONValue], at: String) {
        running = false; observedAt = at; failure = nil
        if let success = result["game_launch_command_succeeded"]?.boolean { launchCommandSucceeded = success }
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
        ["task_id": .string(taskID?.uuidString ?? "unknown"), "started_at": .string(startedAt ?? "unknown"), "app_version": .string(appVersion),
         "runtime_root": .string(root), "fx_path": .string(fxPath ?? "unverified"),
         "fx_version": .string(fxVersion ?? "unverified"), "stage": .string(current.rawValue),
         "stages": .object(evidence.reduce(into: [:]) { $0[$1.key.rawValue] = .string($1.value) }),
         "error_code": .string(failure?.code ?? "none"),
         "error_summary": .string(failure?.details["summary"]?.text ?? failure?.message("en") ?? ""),
         "game_launch_command_succeeded": launchCommandSucceeded.map { .bool($0) } ?? .null,
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
    var taskID = UUID()
    var startedAt = Date()
    var phase: EnvironmentWorkflowPhase = .idle
    var completedSteps = 0
    var launchesGame = false
    var failure: ErrorState?
    var needsRestartApproval = false
    var deploymentStage: String?
    var evidence: [String: JSONValue] = [:]
    var totalSteps: Int { launchesGame ? 6 : 5 }
    var active: Bool { ![.idle, .completed, .failed, .cancelled].contains(phase) }
    var showsProgress: Bool { phase != .failed && phase != .cancelled }
    var fraction: Double { phase == .completed ? 1 : min(Double(completedSteps) / Double(totalSteps), 0.99) }
    // FEX reports a verified runtime as normal/compatible rather than the
    // generic "verified" observation used by other components.
    static func setupObservationVerified(component: String, current: String, passed: Bool, blocked: Bool, hasChanges: Bool, fexRuntime: String?) -> Bool {
        guard !blocked && !hasChanges else { return false }
        return passed || (component == "fex" && ["normal", "compatible"].contains(current) && fexRuntime == "ready")
    }
    // Presentation gate only: completion requires a ready inspection bound to
    // the current target, in addition to the completed deployment state.
    func canShowSetupCompletion(busy: Bool, deploymentCompleted: Bool, hasCurrentBinding: Bool, hasRequiredObservations: Bool, inspectionReady: Bool) -> Bool {
        return !busy && deploymentCompleted && hasCurrentBinding && hasRequiredObservations && inspectionReady
    }
}

// Scope each LED to the fact it actually observes. No EAC/multiplayer success probe exists.
struct DashboardStatus: Equatable {
    enum Tone { case success, working, failed, unknown }
    let tone: Tone
    let textKey: String
    static func resolve(key: String, stage: LaunchStage?, session: LaunchSession,
                        workflow: EnvironmentWorkflow, evidence: [String: JSONValue], stale: Bool) -> Self {
        let stages: [LaunchStage] = key == "fx_host_running"
            ? [.startingFX, .checkingFXEntry, .waitingForFXReady, .verifyingFXIdentity]
            : stage.map { [$0] } ?? []
        let processing = session.running && stages.contains(session.current)
            || (key == "fx_host_running" && workflow.phase == .startingFX)
            || (key == "ssh_connected" && workflow.phase == .connecting)
        if processing { return Self(tone: .working, textKey: "ui.157") }
        guard !stale else { return Self(tone: .unknown, textKey: "ui.368") }
        if stages.contains(where: { session.evidence[$0] == "failed" }) {
            return Self(tone: .failed, textKey: "ui.125")
        }
        switch key {
        case "ssh_connected" where evidence[key]?.boolean == true && evidence["guest_ready"]?.boolean == true:
            return Self(tone: .success, textKey: "ui.dashboard.connected")
        case "fx_host_running" where evidence[key]?.boolean == true:
            return Self(tone: .success, textKey: "ui.dashboard.process")
        case "steam_running" where evidence[key]?.boolean == true || (evidence["steam_process_count"]?.integer ?? 0) > 0:
            return Self(tone: .success, textKey: "ui.dashboard.process")
        default:
            return Self(tone: .unknown, textKey: "ui.368")
        }
    }
}

/// Stored timestamps remain UTC; conversion is presentation-only.
enum LogTimestamp {
    private static let lock = NSLock()
    private static let embeddedPattern = try! NSRegularExpression(pattern: #"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z"#)
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let standard = ISO8601DateFormatter()
    private static let local: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
    static func display(_ raw: String, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        lock.lock(); defer { lock.unlock() }
        guard let date = fractional.date(from: raw) ?? standard.date(from: raw) else { return raw }
        local.timeZone = timeZone
        return local.string(from: date)
    }
    static func displayTimestamps(in text: String, timeZone: TimeZone = .autoupdatingCurrent) -> String {
        var result = text
        let matches = embeddedPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: display(String(result[range]), timeZone: timeZone))
        }
        return result
    }
}
