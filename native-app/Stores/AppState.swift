import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selection: Page? = .dashboard
    @Published var languageCode = NativeLocalization.initialLanguage {
        didSet {
            guard !NativeLocalization.isolatedUXSmoke else { return }
            UserDefaults.standard.set(languageCode, forKey: "NativeLanguage")
            let systemLanguage = languageCode == "zh-CN" ? "zh-Hans" : languageCode == "zh-TW" ? "zh-Hant" : languageCode
            UserDefaults.standard.set([systemLanguage, "en"], forKey: "AppleLanguages")
        }
    }
    let updates = AppUpdateManager()
    var chinese: Bool {
        get { languageCode.hasPrefix("zh") }
        set { languageCode = newValue ? "zh-CN" : "en" }
    }
    @Published var operationSelection: NativeOperation?
    @Published var pendingAction: GUIAction?
    let credentials = SessionCredentialManager()
    @Published var runtimeRoot = NativeLocalization.isolatedUXSmoke ? "" : UserDefaults.standard.string(forKey: "NativeRememberedRuntimeRoot") ?? "" {
        didSet { if oldValue != runtimeRoot { credentials.clear(); guiSnapshots = [:]; targetInspection = [:]; targetInspectionError = nil; inspectedTarget = nil } }
    }
    @Published private(set) var targetInspection: [String: JSONValue] = [:]
    @Published private(set) var targetInspectionError: ErrorState?
    @Published private(set) var inspectingTarget = false
    private var inspectedTarget: String?
    var targetInspectionIdentity: String { runtimeRoot + "|" + pythonURL.path }
    func inspectTargetIfNeeded(force: Bool = false) {
        let root = runtimeRoot, identity = targetInspectionIdentity
        guard (hasLoaded || error != nil), !root.isEmpty, !tasks.busy, force || inspectedTarget != identity else { return }
        inspectingTarget = true
        targetInspection = [:]; targetInspectionError = nil
        tasks.start { [weak self] in
            guard let self else { return }
            defer { self.inspectingTarget = false }
            do {
                let config = try BridgeConfiguration.bundled(python: self.pythonURL)
                let reply = try await self.bridge.request("inspect_launch_target", configuration: config, params: ["runtime_root": .string(root)])
                guard self.targetInspectionIdentity == identity else { return }
                guard reply.result["scope"]?.text == "selected_target_file_metadata_only",
                      reply.result["archive_files_match"]?.boolean != nil,
                      reply.result["fx_executable_present"]?.boolean != nil else { throw ErrorState("PROTOCOL_ERROR") }
                self.targetInspection = reply.result
                self.inspectedTarget = identity
            } catch {
                guard self.targetInspectionIdentity == identity else { return }
                self.targetInspectionError = error as? ErrorState ?? ErrorState("CORE_UNAVAILABLE")
                self.inspectedTarget = identity
            }
        }
    }
    @Published private(set) var performanceSnapshot: [String: JSONValue] = [:]
    @Published private(set) var guiRecords: [String: GUIOperationRecord] = [:]
    @Published private(set) var guiSnapshots: [String: [String: JSONValue]] = [:]
    @Published private(set) var operationResult: [String: JSONValue] = [:]
    @Published private(set) var operationError: ErrorState?
    @Published private(set) var operationEvents: [[String: JSONValue]] = []
    @Published private(set) var runtimeLogs: [[String: JSONValue]] = []
    @Published private(set) var launchSession = LaunchSession()
    private var operationGeneration = UUID()
    @Published var appearance: Appearance = .dark
    @Published var pythonURL = AppState.savedPythonURL {
        didSet { UserDefaults.standard.set(pythonURL.path, forKey: "NativePythonPath") }
    }
    private static var savedPythonURL: URL {
        if NativeLocalization.isolatedUXSmoke { return URL(fileURLWithPath: "/usr/bin/python3") }
        if let path = UserDefaults.standard.string(forKey: "NativePythonPath"), FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: "/usr/bin/python3")
    }
    @Published private(set) var results: [String: [String: JSONValue]] = [:]
    @Published private(set) var observedAt: String?
    @Published private(set) var error: ErrorState?
    @Published private(set) var sessionLogs: [String] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var stale = false
    @Published private(set) var refreshing = false
    let tasks = TaskManager()
    private let bridge = BridgeService()

    func t(_ key: String) -> String { NativeStrings.text(key, language: languageCode) }
    func pageTitle(_ page: Page) -> String { page.title(languageCode) }
    func runOperation(_ method: String, params: [String: JSONValue] = [:]) {
        guard !tasks.busy else { return }
        let generation = UUID(); operationGeneration = generation
        let selectedRoot = runtimeRoot
        var redactor = credentials.redactor
        if method == "launch_game" { launchSession.begin(root: selectedRoot); recordLaunch() }
        if method == "observe_launch", selectedRoot != launchSession.root { launchSession.begin(root: selectedRoot) }
        guiRecords[method] = GUIOperationRecord(method: method, target: selectedRoot)
        if GUIAction(rawValue: method) != nil { guiSnapshots = [:] }
        operationError = nil; operationResult = [:]; operationEvents = []
        tasks.start { [weak self] in
            guard let self else { return }
            do {
                let config = try BridgeConfiguration.bundled(python: self.pythonURL)
                var input = params.filter { !["password","passphrase","sudo_password"].contains($0.key) }
                if !selectedRoot.isEmpty { input["runtime_root"] = .string(selectedRoot) }
                if let note = input["note"]?.text { input["note"] = .string(redactor.text(note)) }
                if method == "save_configuration", let value = input["configuration"], redactor.containsSecret(value) { throw ErrorState("SENSITIVE_CONFIGURATION") }
                if ["launch_game","test_ssh","test_guest_sudo","connect_fx","inspect_guest_environment","start_steam","inspect_guest","apply_performance","save_network_snapshot"].contains(method) {
                    let metadata = try await self.bridge.request("read_configuration", configuration: config)
                    guard let revision = metadata.result["revision"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                    await self.credentials.prepare(for: selectedRoot + "|" + revision)
                    input.merge(try self.credentials.parameters(for: selectedRoot + "|" + revision)) { _, new in new }
                    redactor = self.credentials.redactor
                    input["credential_revision"] = .string(revision)
                }
                let eventRedactor = redactor
                let authInput = input
                let credentialTarget = selectedRoot + "|" + (input["credential_revision"]?.text ?? "")
                let reply = try await self.bridge.request(method, configuration: config, timeout: method == "launch_game" || method == "apply_performance" ? 900 : 90, params: input) { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.operationGeneration == generation else { return }
                        if method == "launch_game" { self.launchSession.consume(event) }
                        if event["kind"]?.text == "credential_status",
                           let role = event["credential_kind"]?.text.flatMap(CredentialKind.init(rawValue:)) {
                            if event["status"]?.text == "rejected" { self.credentials.reject(role) }
                            else if event["status"]?.text == "authenticated", let value = authInput[role.bridgeField]?.text {
                                await self.credentials.authenticated(role, value: value, target: credentialTarget)
                                if self.credentials.saved.contains(role), !selectedRoot.isEmpty {
                                    UserDefaults.standard.set(selectedRoot, forKey: "NativeRememberedRuntimeRoot")
                                }
                            }
                        }
                        let safeEvent = eventRedactor.event(event)
                        self.operationEvents.append(safeEvent)
                        self.runtimeLogs.append(safeEvent)
                        if self.runtimeLogs.count > 500 { self.runtimeLogs.removeFirst(self.runtimeLogs.count - 500) }
                        if self.operationEvents.count > 200 { self.operationEvents.removeFirst(self.operationEvents.count - 200) }
                    }
                }
                if let action = GUIAction(rawValue: method), !action.accepts(reply.result) { throw ErrorState("PROTOCOL_ERROR", method: method) }
                if reply.result["fx_host_running"]?.boolean == false { self.guiSnapshots = [:] }
                self.operationResult = reply.result
                if method == "read_performance" { self.performanceSnapshot = reply.result }
                if GUIAction(rawValue: method) != nil, self.runtimeRoot == selectedRoot { self.guiSnapshots[method] = reply.result }
                self.guiRecords[method]?.finish()
                self.recordGUIOperation(method)
                if method == "launch_game" || method == "observe_launch" { self.launchSession.complete(reply.result, at: reply.observedAt); self.recordLaunch() }
                self.appendLog(method + ": COMPLETED")
            } catch {
                let failure = error as? ErrorState ?? ErrorState("PROTOCOL_ERROR", method: method)
                self.operationError = ErrorState(failure.code, method: failure.method, details: redactor.diagnostic(failure.details))
                if failure.code == "SUDO_AUTH_FAILED" { self.credentials.reject(.sudo) }
                if failure.code == "SSH_AUTH_FAILED" { self.credentials.reject(.ssh) }
                if method == "launch_game" || method == "observe_launch", let failure = self.operationError {
                    if method == "observe_launch" { self.launchSession = LaunchSession() }
                    self.launchSession.fail(failure)
                    self.recordLaunch()
                }
                self.guiRecords[method]?.finish(self.operationError)
                self.recordGUIOperation(method)
                if GUIAction(rawValue: method) != nil, ["AUTH_REQUIRED","SSH_AUTH_FAILED","SUDO_AUTH_FAILED","CHANGE_CONFIRMATION_REQUIRED","RUNTIME_ROOT_REQUIRED"].contains(failure.code), self.operationSelection == nil {
                    self.operationSelection = NativeOperation(method: method)
                }
                self.appendLog(method + ": " + (self.operationError?.code ?? "UNKNOWN"))
            }
        }
    }
    func perform(_ action: GUIAction) {
        guard !tasks.busy else { return }
        operationError = nil; operationResult = [:]; operationEvents = []
        if action == .game || runtimeRoot.isEmpty { operationSelection = NativeOperation(method: action.rawValue) }
        else if action.needsReview { pendingAction = action }
        else { runOperation(action.rawValue, params: ["confirmed": .bool(true)]) }
    }
    var latestGUIEvidence: [String: JSONValue] {
        guiRecords.values.filter { $0.target == runtimeRoot && $0.status == .succeeded && guiSnapshots[$0.method] != nil }
            .max { $0.startedAt < $1.startedAt }.flatMap { guiSnapshots[$0.method] } ?? [:]
    }
    func confirmPendingAction(_ action: GUIAction) {
        pendingAction = nil
        runOperation(action.rawValue, params: ["confirmed": .bool(true)])
    }
    private func recordGUIOperation(_ method: String) {
        guard let record = guiRecords[method] else { return }
        let details: [String: JSONValue] = ["operation": .string(method), "started_at": .string(ISO8601DateFormatter().string(from: record.startedAt)),
            "ended_at": .string(ISO8601DateFormatter().string(from: record.endedAt ?? Date())), "status": .string(record.status.rawValue),
            "error_code": .string(record.error?.code ?? "none")]
        if let data = try? JSONEncoder().encode(JSONValue.object(details)), let text = String(data: data, encoding: .utf8) {
            runtimeLogs.append(["at": .string(ISO8601DateFormatter().string(from: Date())), "source": .string("Native action"), "level": .string(record.error == nil ? "INFO" : "ERROR"), "message": .string(credentials.redactor.text(text))])
            if runtimeLogs.count > 500 { runtimeLogs.removeFirst(runtimeLogs.count - 500) }
        }
    }
    func prepareCredentials(interactive: Bool = false) async {
        guard !NativeLocalization.isolatedUXSmoke else { return }
        do {
            let config = try BridgeConfiguration.bundled(python: pythonURL)
            let metadata = try await bridge.request("read_configuration", configuration: config)
            guard let revision = metadata.result["revision"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
            await credentials.prepare(for: runtimeRoot + "|" + revision, interactive: interactive)
        } catch { appendLog("credential target unavailable") }
    }
    private func recordLaunch() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let record = launchSession.diagnostic(appVersion: version + " (" + build + ")")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(JSONValue.object(record)), let text = String(data: bytes, encoding: .utf8) else { return }
        runtimeLogs.append(["at": .string(ISO8601DateFormatter().string(from: Date())), "source": .string("Native launch"),
                            "level": .string(launchSession.failure == nil ? "INFO" : "ERROR"),
                            "message": .string(credentials.redactor.text(text))])
        if runtimeLogs.count > 500 { runtimeLogs.removeFirst(runtimeLogs.count - 500) }
    }
    func confirmMainMenu() { launchSession.confirmMainMenu(); recordLaunch() }
    func confirmSinglePlayer() { launchSession.confirmSinglePlayer(); recordLaunch() }
    func endSession() { tasks.cancel(); credentials.clear() }
    func value(_ method: String, _ key: String) -> String { results[method]?[key]?.text ?? t("ui.366") }
    func rows(_ method: String, _ key: String) -> [[String: JSONValue]] { results[method]?[key]?.array.map(\.object) ?? [] }
    func refresh() {
        inspectedTarget = nil
        tasks.start { [weak self] in await self?.load() }
    }
    private func load() async {
        refreshing = true
        defer { refreshing = false }
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
        sessionLogs.append("\(ISO8601DateFormatter().string(from: Date()))  \(credentials.redactor.text(line))")
        if sessionLogs.count > 200 { sessionLogs.removeFirst(sessionLogs.count - 200) }
    }
    var logText: String {
        let bridgeLogs = rows("get_logs", "entries").map { ($0["at"]?.text ?? "") + "  " + ($0["message"]?.text ?? "") }
        return credentials.redactor.text((sessionLogs + bridgeLogs).joined(separator: "\n"))
    }
}
