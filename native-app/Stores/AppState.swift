import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selection: Page? = .dashboard
    @Published var languageCode = NativeLocalization.initialLanguage
    var chinese: Bool {
        get { languageCode.hasPrefix("zh") }
        set { languageCode = newValue ? "zh-CN" : "en" }
    }
    @Published var operationSelection: NativeOperation?
    @Published var runtimeRoot = ""
    @Published private(set) var operationResult: [String: JSONValue] = [:]
    @Published private(set) var operationError: ErrorState?
    @Published private(set) var operationEvents: [[String: JSONValue]] = []
    @Published private(set) var runtimeLogs: [[String: JSONValue]] = []
    @Published var appearance: Appearance = .dark
    @Published var pythonURL = URL(fileURLWithPath: "/usr/bin/python3")
    @Published private(set) var results: [String: [String: JSONValue]] = [:]
    @Published private(set) var observedAt: String?
    @Published private(set) var error: ErrorState?
    @Published private(set) var sessionLogs: [String] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var stale = false
    let tasks = TaskManager()
    private let bridge = BridgeService()

    func t(_ zh: String, _ en: String) -> String { NativeLocalization.text(zh, en, language: languageCode) }
    func pageTitle(_ page: Page) -> String { t(page.title(true), page.title(false)) }
    func runOperation(_ method: String, params: [String: JSONValue] = [:]) {
        guard !tasks.busy else { return }
        operationError = nil; operationResult = [:]; operationEvents = []
        tasks.start { [weak self] in
            guard let self else { return }
            do {
                let config = try BridgeConfiguration.bundled(python: self.pythonURL)
                var input = params
                if !self.runtimeRoot.isEmpty { input["runtime_root"] = .string(self.runtimeRoot) }
                let reply = try await self.bridge.request(method, configuration: config, timeout: method == "launch_game" || method == "apply_performance" ? 900 : 90, params: input) { [weak self] event in
                    Task { @MainActor in
                        guard let self else { return }
                        self.operationEvents.append(event)
                        self.runtimeLogs.append(event)
                        if self.runtimeLogs.count > 500 { self.runtimeLogs.removeFirst(self.runtimeLogs.count - 500) }
                        if self.operationEvents.count > 200 { self.operationEvents.removeFirst(self.operationEvents.count - 200) }
                    }
                }
                self.operationResult = reply.result
                self.appendLog(method + ": COMPLETED")
            } catch {
                self.operationError = error as? ErrorState ?? ErrorState("PROTOCOL_ERROR", method: method)
                self.appendLog(method + ": " + (self.operationError?.code ?? "UNKNOWN"))
            }
        }
    }
    func value(_ method: String, _ key: String) -> String { results[method]?[key]?.text ?? t("未知", "Unknown") }
    func rows(_ method: String, _ key: String) -> [[String: JSONValue]] { results[method]?[key]?.array.map(\.object) ?? [] }
    func refresh() {
        tasks.start { [weak self] in await self?.load() }
    }
    private func load() async {
        error = nil
        stale = !results.isEmpty
        do {
            let config = try BridgeConfiguration.bundled(python: pythonURL)
            var snapshot: [String: [String: JSONValue]] = [:]
            var snapshotTime: String?
            for method in ["handshake", "get_launcher_version", "get_system_info", "get_environment_status", "get_dependencies", "list_fx_versions", "get_logs", "get_legacy_catalog"] {
                try Task.checkCancellation()
                let reply = try await bridge.request(method, configuration: config)
                try validate(method, result: reply.result)
                snapshot[method] = reply.result
                snapshotTime = reply.observedAt
                appendLog("\(method): OK [\(reply.requestID)]")
            }
            results = snapshot; observedAt = snapshotTime; hasLoaded = true; stale = false
        } catch {
            let failure = error as? ErrorState ?? ErrorState(error is CancellationError ? "CANCELLED" : "PROTOCOL_ERROR")
            self.error = failure
            appendLog("\(failure.method): \(failure.code)")
        }
    }
    private func validate(_ method: String, result: [String: JSONValue]) throws {
        let valid: Bool
        switch method {
        case "get_launcher_version": valid = result["version"]?.text != nil
        case "get_system_info": valid = ["os", "os_version", "arch", "python"].allSatisfy { result[$0]?.text != nil }
        case "get_environment_status": valid = result["status"]?.text == "unverified" && result["checks"] != nil
        case "get_dependencies": valid = result["items"] != nil
        case "list_fx_versions": valid = result["candidates"] != nil && result["scan_incomplete"]?.boolean != nil
        case "get_logs": valid = result["entries"] != nil && result["source"]?.text == "bridge_process_session"
        default: valid = true
        }
        if !valid { throw ErrorState("PROTOCOL_ERROR", method: method) }
    }
    private func appendLog(_ line: String) {
        sessionLogs.append("\(ISO8601DateFormatter().string(from: Date()))  \(line)")
        if sessionLogs.count > 200 { sessionLogs.removeFirst(sessionLogs.count - 200) }
    }
    var logText: String {
        let bridgeLogs = rows("get_logs", "entries").map { ($0["at"]?.text ?? "") + "  " + ($0["message"]?.text ?? "") }
        return (sessionLogs + bridgeLogs).joined(separator: "\n")
    }
}
