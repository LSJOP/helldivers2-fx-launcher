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
    mutating func begin(root: String) { self = LaunchSession(); self.root = root; current = .checkingEnvironment; running = true }
    mutating func consume(_ event: [String: JSONValue]) {
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
    mutating func confirmMainMenu() {
        guard !running, processDetected else { return }
        mainMenuConfirmedAt = ISO8601DateFormatter().string(from: Date())
    }
    mutating func confirmSinglePlayer() {
        guard !running, processDetected, mainMenuConfirmedAt != nil else { return }
        singlePlayerConfirmedAt = ISO8601DateFormatter().string(from: Date())
    }
}
