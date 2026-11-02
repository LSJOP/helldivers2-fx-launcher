import Foundation

enum LaunchStage: String, CaseIterable, Identifiable {
    case idle = "Idle", checkingEnvironment = "CheckingEnvironment", startingFX = "StartingFX"
    case checkingFXEntry = "CheckingFXEntry"
    case waitingForGuest = "WaitingForGuest", checkingCompatibility = "CheckingCompatibility"
    case startingSteam = "StartingSteam", launchingGame = "LaunchingGame", waitingForGame = "WaitingForGame"
    case gameProcessDetected = "GameProcessDetected", checkingEAC = "CheckingEAC", failed = "Failed"
    var id: String { rawValue }
    func title(_ zh: Bool) -> String {
        switch self {
        case .idle: return zh ? "尚未启动" : "Idle"
        case .checkingEnvironment: return zh ? "检查本地环境" : "Checking local environment"
        case .startingFX: return zh ? "FX 宿主进程（非 Guest 就绪）" : "FX host processes (not Guest readiness)"
        case .checkingFXEntry: return zh ? "FX 启动入口检查" : "FX launch entry check"
        case .waitingForGuest: return zh ? "等待 Guest / SSH" : "Waiting for Guest / SSH"
        case .checkingCompatibility: return zh ? "检查兼容性配置" : "Checking compatibility"
        case .startingSteam: return zh ? "启动 Steam" : "Starting Steam"
        case .launchingGame: return zh ? "发送游戏启动请求" : "Requesting game launch"
        case .waitingForGame: return zh ? "等待游戏进程" : "Waiting for game process"
        case .gameProcessDetected: return zh ? "已检测到游戏进程" : "Game process detected"
        case .checkingEAC: return zh ? "EAC 独立检测" : "Separate EAC check"
        case .failed: return zh ? "启动操作需要处理" : "Launch needs attention"
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
        running = false; observedAt = at
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
        if error.code == "GAME_EXITED" {
            evidence[.gameProcessDetected] = "unverified"; stageSequences[.gameProcessDetected] = Int.max
            mainMenuConfirmedAt = nil; singlePlayerConfirmedAt = nil
        }
    }
    // A structured record, never evidence of a menu/window merely from process presence.
    func diagnostic(appVersion: String) -> [String: JSONValue] {
        ["started_at": .string(startedAt ?? "unknown"), "app_version": .string(appVersion),
         "runtime_root": .string(root), "fx_path": .string(fxPath ?? "unverified"),
         "fx_version": .string(fxVersion ?? "unverified"), "stage": .string(current.rawValue),
         "stages": .object(evidence.reduce(into: [:]) { $0[$1.key.rawValue] = .string($1.value) }),
         "error_code": .string(failure?.code ?? "none"),
         "error_summary": .string(failure?.details["summary"]?.text ?? failure?.message(false) ?? ""),
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
