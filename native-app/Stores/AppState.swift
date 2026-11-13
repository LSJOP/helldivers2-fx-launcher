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
    @Published var networkIPv6: [String: JSONValue] = [:]
    @Published var networkPlan: [String: JSONValue] = [:]
    @Published var networkRows: [[String: JSONValue]] = []
    @Published private(set) var networkLaunchPending = false
    var networkDiagnosticRunning: Bool { tasks.busy && guiRecords["run_network_diagnostics"]?.status == .running }
    @Published var networkDiagnosticError: ErrorState?
    @Published var networkError: ErrorState?
    @Published var networkBackup = ""
    @Published var networkShowConfirmation = false
    @Published var guestRestorePath = ""
    @Published var pendingAction: GUIAction?
    let credentials = SessionCredentialManager()
    @Published var firstRunPlan: DeploymentPlan?
    @Published var firstRunState: DeploymentState = .NotChecked
    @Published var firstRunFEX: [String: JSONValue] = [:]
    @Published var firstRunFEXTicket: UUID?
    @Published var firstRunFEXRestore: UUID?
    @Published var firstRunReceipt: DeploymentReceipt?
    @Published var firstRunReceipts: [DeploymentReceipt] = []
    @Published var firstRunFailure: String?
    private var firstRunEventGeneration: UUID?
    func firstRunAction(_ method: String, receipt: UUID? = nil, selected: Set<String> = []) {
        guard !tasks.busy else { return }
        if method == "first_run_fex_install" { firstRunFEXRestore = receipt }
        let generation = UUID(); firstRunEventGeneration = generation
        let root = runtimeRoot, launch = fxSelection.launchParameters(runtimeRoot: runtimeRoot)
        let plan = firstRunPlan
        firstRunFailure = nil
        firstRunState = method == "first_run_detect" || ["first_run_fex_audit", "first_run_fex_build"].contains(method) ? .Checking : method == "first_run_receipts" ? firstRunState : .AwaitingAuthorization
        tasks.start { [weak self] in
            guard let self else { return }
            do {
                var input = launch
                input["confirmed"] = .bool(true)
                if method != "first_run_receipts" {
                    let metadata = try await self.core.request("read_configuration")
                    let revision = metadata.result["revision"]?.text ?? ""
                    let binding = try await self.core.request("credential_target", timeout: 45, params: launch)
                    guard let identity = binding.result["identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                    let target = root + "|" + revision + "|" + identity
                    if let scope = self.credentials.scope, scope != target { self.clearSessionCredentials() }
                    await self.credentials.prepare(for: target)
                    // Setup owns an isolated SSH master; host-only metadata can omit a
                    // boot ID. Keep the prior expected boot for the newly authenticated
                    // backend to verify, rather than treating omission as identity loss.
                    if let boot = binding.result["guest_boot"]?.text { try self.credentials.bindGuest(boot) }
                    input.merge(try self.credentials.parameters(for: target)) { _, value in value }
                    input["credential_revision"] = .string(revision)
                    input["credential_host_identity"] = .string(identity)
                }
                if method == "first_run_deploy", let plan {
                    input["deployment_plan"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(plan))
                    input["approved_steps"] = .array(plan.executable.map { .string($0.id) })
                    input["restart_vm_approved"] = .bool(plan.executable.contains { $0.needsRestart })
                    self.firstRunState = .Deploying
                }
                if let receipt { input["receipt_id"] = .string(receipt.uuidString); input["approved_steps"] = .array(selected.sorted().map { .string($0) }) }
                var credentialTarget = root + "|" + (input["credential_revision"]?.text ?? "") + "|" + (input["credential_host_identity"]?.text ?? "")
                let authInput = input
                let requestCredentialTarget = credentialTarget
                let reply = try await self.core.request(method, timeout: method == "first_run_fex_build" ? 6500 : method == "first_run_deploy" ? 1500 : method.hasPrefix("first_run_fex_") ? 400 : 180, params: input) { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.firstRunEventGeneration == generation else { return }
                        if event["kind"]?.text == "credential_status", event["status"]?.text == "authenticated",
                           let role = event["credential_kind"]?.text.flatMap(CredentialKind.init(rawValue:)), let value = authInput[role.bridgeField]?.text {
                            await self.credentials.authenticated(role, value: value, target: requestCredentialTarget)
                        }
                        if let raw = event["deployment_state"]?.text, let status = DeploymentState(rawValue: raw) { self.firstRunState = status }
                    }
                }
                if let transition = reply.result["reboot_transition"]?.object {
                    guard method == "first_run_deploy", authInput["restart_vm_approved"]?.boolean == true,
                          let old = transition["from"]?.text, let new = transition["to"]?.text,
                          let identity = transition["host_identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                    let reboundTarget = root + "|" + (authInput["credential_revision"]?.text ?? "") + "|" + identity
                    try self.credentials.acceptExpectedReboot(from: old, to: new, target: credentialTarget, reboundTarget: reboundTarget)
                    credentialTarget = reboundTarget
                }
                if reply.result["ssh_password_verified"]?.boolean == true, let value = authInput["password"]?.text {
                    await self.credentials.authenticated(.ssh, value: value, target: credentialTarget)
                }
                self.firstRunEventGeneration = nil
                if let review = reply.result["fex_audit"]?.object {
                    if let boot = reply.result["guest_boot"]?.text { try self.credentials.bindGuest(boot) }
                    self.firstRunFEX = review
                    self.firstRunFEXTicket = reply.result["fex_ticket"]?.text.flatMap(UUID.init(uuidString:))
                    self.firstRunFEXRestore = reply.result["fex_restore_ticket"]?.text.flatMap(UUID.init(uuidString:))
                    self.firstRunState = .NeedsConfiguration
                }
                if let value = reply.result["plan"] {
                    let plan = try JSONDecoder().decode(DeploymentPlan.self, from: JSONEncoder().encode(value))
                    try self.credentials.bindGuest(plan.snapshot.boot)
                    self.firstRunPlan = plan
                    self.firstRunState = plan.detectionState
                }
                if let value = reply.result["receipt"] {
                    let receipt = try JSONDecoder().decode(DeploymentReceipt.self, from: JSONEncoder().encode(value))
                    self.firstRunReceipt = receipt; self.firstRunState = receipt.state; self.firstRunFailure = receipt.failure
                    self.firstRunPlan = nil // Every subsequent operation requires a fresh scan.
                }
                if let value = reply.result["next_plan"] {
                    let next = try JSONDecoder().decode(DeploymentPlan.self, from: JSONEncoder().encode(value))
                    try self.credentials.bindGuest(next.snapshot.boot)
                    self.firstRunPlan = next
                }
                if let value = reply.result["receipts"] { self.firstRunReceipts = try JSONDecoder().decode([DeploymentReceipt].self, from: JSONEncoder().encode(value)) }
            } catch {
                self.firstRunEventGeneration = nil
                let code = (error as? ErrorState)?.code ?? (error as? CoreError)?.code ?? "DEPLOYMENT_FAILED"
                self.firstRunFailure = code
                if method.hasPrefix("first_run_fex_"), let failure = error as? ErrorState {
                    self.firstRunFEX["error"] = .string(code)
                    self.firstRunFEX["summary"] = failure.details["summary"]
                }
                self.firstRunState = code == "RECOVERY_REQUIRED" ? .RecoveryRequired : .Failed
                if ["CREDENTIAL_SCOPE_CHANGED", "TARGET_CHANGED", "FX_IDENTITY_UNVERIFIED", "FX_ENTRY_MISMATCH"].contains(code) { self.clearSessionCredentials(); self.firstRunPlan = nil }
                if code == "SSH_AUTH_FAILED" { self.credentials.reject(.ssh) }
                if code == "SUDO_AUTH_FAILED" { self.credentials.reject(.sudo) }
            }
        }
    }

    @Published private(set) var fxSelection = FXSelectionManager(defaults: NativeLocalization.isolatedUXSmoke ? nil : .standard)
    @Published private(set) var fxSelectionIssue = false
    var fxStatus: String {
        guard fxSelection.selected != nil else {
            return t(!fxSelection.scanned ? "ui.208" : fxSelection.candidates.isEmpty ? "ui.fx.none" : "ui.fx.choose")
        }
        return t(fxSelection.automatic ? "ui.fx.autoPending" : "ui.fx.defaultPending")
    }
    var fxVersion: String { fxSelection.selected?["version"]?.text ?? t("ui.366") }
    private func applyFXScan(_ result: [String: JSONValue]) {
        let previous = fxSelection.selectedPath
        fxSelection.reconcile(result["candidates"]?.array.map(\.object) ?? [], incomplete: result["scan_incomplete"]?.boolean != false)
        if previous != fxSelection.selectedPath { clearSessionCredentials(); clearNetworkState(); guiSnapshots = [:]; performanceConfigurationState = PerformanceConfigurationState(); inspectedTarget = nil }
        runtimeRoot = fxSelection.selectedPath ?? ""
    }
    func selectFX(_ path: String) {
        guard !tasks.busy else { return }
        if fxSelection.selectedPath != path { clearSessionCredentials(); clearNetworkState(); guiSnapshots = [:]; performanceConfigurationState = PerformanceConfigurationState() }
        fxSelection.select(path)
        runtimeRoot = fxSelection.selectedPath ?? ""
        inspectedTarget = nil
    }
    func scanFX(manualPath: String? = nil, openingLaunch: Bool = false) {
        guard !tasks.busy else { return }
        fxSelectionIssue = false
        tasks.start { [weak self] in
            guard let self else { return }
            do {
                let paths = self.fxSelection.scanPaths + (manualPath.map { [.string($0)] } ?? [])
                let reply = try await self.core.request("list_fx_versions", params: ["selected_paths": .array(paths), "runtime_root": .string(self.runtimeRoot)])
                self.results["list_fx_versions"] = reply.result
                self.applyFXScan(reply.result)
                if let rawPath = manualPath {
                    let manualPath = URL(fileURLWithPath: rawPath).resolvingSymlinksInPath().path
                    self.fxSelectionIssue = !self.fxSelection.candidates.contains { $0["path"]?.text == manualPath }
                    if self.fxSelection.selectedPath != manualPath { self.clearSessionCredentials(); self.guiSnapshots = [:]; self.performanceConfigurationState = PerformanceConfigurationState() }
                    self.fxSelection.select(manualPath)
                    self.runtimeRoot = self.fxSelection.selectedPath ?? ""
                }
                if openingLaunch {
                    if self.fxSelection.selected == nil { self.selection = .fx }
                    else { self.operationSelection = NativeOperation(method: "launch_game") }
                }
            } catch {
                self.operationError = error as? ErrorState ?? ErrorState("CORE_UNAVAILABLE")
            }
        }
    }
    @Published var runtimeRoot = "" {
        didSet {
            if oldValue != runtimeRoot {
                clearSessionCredentials(); clearNetworkState(); guiSnapshots = [:]; performanceConfigurationState = PerformanceConfigurationState(); targetInspection = [:]; targetInspectionError = nil; inspectedTarget = nil
                if !runtimeRoot.isEmpty, !NativeLocalization.isolatedUXSmoke {
                    UserDefaults.standard.set(runtimeRoot, forKey: "NativeRememberedRuntimeRoot")
                }
            }
        }
    }
    @Published private(set) var targetInspection: [String: JSONValue] = [:]
    @Published private(set) var targetInspectionError: ErrorState?
    @Published private(set) var inspectingTarget = false
    private var inspectedTarget: String?
    var targetInspectionIdentity: String { runtimeRoot + "|" + (fxSelection.selectedPath ?? "") + "|" + fxVersion }
    func inspectTargetIfNeeded(force: Bool = false) {
        let root = runtimeRoot, identity = targetInspectionIdentity, launchParameters = fxSelection.launchParameters(runtimeRoot: runtimeRoot)
        guard (hasLoaded || error != nil), !root.isEmpty, !tasks.busy, force || inspectedTarget != identity else { return }
        inspectingTarget = true
        targetInspection = [:]; targetInspectionError = nil
        tasks.start { [weak self] in
            guard let self else { return }
            defer { self.inspectingTarget = false }
            do {
                let reply = try await self.core.request("inspect_launch_target", params: launchParameters)
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
    @Published private(set) var performanceConfigurationState = PerformanceConfigurationState()
    var performanceConfiguration: [String: JSONValue] { performanceConfigurationState.snapshot }
    var performancePreview: [String: JSONValue] { performanceConfigurationState.preview }
    var editedPerformance: [String: JSONValue] {
        get { performanceConfigurationState.edited }
        set { performanceConfigurationState.edited = newValue; performanceConfigurationState.preview = [:] }
    }
    @Published private(set) var performanceSnapshot: [String: JSONValue] = [:]
    @Published private(set) var guiRecords: [String: GUIOperationRecord] = [:]
    @Published private(set) var guiSnapshots: [String: [String: JSONValue]] = [:]
    @Published private(set) var sshConfiguration: [String: JSONValue] = [:]
    @Published private(set) var sshConnectionTarget: [String: JSONValue] = [:]
    @Published private(set) var operationResult: [String: JSONValue] = [:]
    @Published private(set) var operationError: ErrorState?
    @Published private(set) var operationEvents: [[String: JSONValue]] = []
    @Published private(set) var runtimeLogs: [[String: JSONValue]] = []
    @Published private(set) var launchSession = LaunchSession()
    private var operationGeneration = UUID()
    @Published var appearance: Appearance = .dark
    @Published private(set) var results: [String: [String: JSONValue]] = [:]
    @Published private(set) var observedAt: String?
    @Published private(set) var error: ErrorState?
    @Published private(set) var sessionLogs: [String] = []
    @Published private(set) var hasLoaded = false
    @Published private(set) var stale = false
    @Published private(set) var refreshing = false
    @Published private(set) var fieldErrors: [String: String] = [:]
    let tasks = TaskManager()
    private let core = NativeCoreService()

    func t(_ key: String) -> String { NativeStrings.text(key, language: languageCode) }
    func pageTitle(_ page: Page) -> String { page.title(languageCode) }
    func runOperation(_ method: String, params: [String: JSONValue] = [:]) {
        guard !tasks.busy else { return }
        let generation = UUID(); operationGeneration = generation
        let selectedRoot = runtimeRoot
        let launchParameters = fxSelection.launchParameters(runtimeRoot: selectedRoot)
        var redactor = credentials.redactor
        if method == "run_network_diagnostics" { networkRows = []; networkDiagnosticError = nil }
        if method.hasSuffix("steamos_ipv6") { networkError = nil; if method != "apply_steamos_ipv6" { networkPlan = [:] } }
        if method == "launch_game" { launchSession.begin(root: selectedRoot); recordLaunch() }
        if method == "observe_launch", selectedRoot != launchSession.root { launchSession.begin(root: selectedRoot) }
        guiRecords[method] = GUIOperationRecord(method: method, target: selectedRoot)
        if GUIAction(rawValue: method) != nil { guiSnapshots = [:] }
        operationError = nil; operationResult = [:]; operationEvents = []
        if method.hasPrefix("performance_") { performanceConfigurationState.preview = [:] }
        tasks.start { [weak self] in
            guard let self else { return }
            do {
                var input = params.filter { !["password","passphrase","sudo_password"].contains($0.key) }
                if !selectedRoot.isEmpty { input["runtime_root"] = .string(selectedRoot) }
                if ["launch_game", "preflight_launch", "observe_launch", "connect_fx", "inspect_guest_environment", "check_fx_state", "start_fx", "start_steam", "test_ssh", "test_guest_sudo", "restore_guest_ipv6", "read_steamos_ipv6", "preview_steamos_ipv6", "apply_steamos_ipv6", "run_network_diagnostics"].contains(method) {
                    input.merge(launchParameters) { _, selected in selected }
                }
                if let note = input["note"]?.text { input["note"] = .string(redactor.text(note)) }
                if method == "save_configuration", let value = input["configuration"], redactor.containsSecret(value) { throw ErrorState("SENSITIVE_CONFIGURATION") }
                if ["launch_game","test_ssh","test_guest_sudo","restore_guest_ipv6","connect_fx","inspect_guest_environment","start_steam","inspect_guest","apply_performance","save_network_snapshot","apply_steamos_ipv6"].contains(method) {
                    input.merge(launchParameters) { _, selected in selected }
                    let metadata = try await self.core.request("read_configuration")
                    guard let revision = metadata.result["revision"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                    if method == "test_ssh" {
                        let ssh = metadata.result["configuration"]?.object["ssh"]?.object ?? [:]
                        self.sshConnectionTarget = ["host": ssh["host"] ?? .null, "port": ssh["port"] ?? .null,
                                                    "username": ssh["username"] ?? .null]
                    }
                    let binding = try await self.core.request("credential_target", timeout: 45, params: launchParameters)
                    guard let identity = binding.result["identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                    let target = selectedRoot + "|" + revision + "|" + identity
                    if let scope = self.credentials.scope, scope != target { self.clearSessionCredentials() }
                    await self.credentials.prepare(for: target)
                    try self.credentials.bindGuest(binding.result["guest_boot"]?.text)
                    input.merge(try self.credentials.parameters(for: target)) { _, new in new }
                    input["credential_host_identity"] = .string(identity)
                    redactor = self.credentials.redactor
                    input["credential_revision"] = .string(revision)
                }
                let eventRedactor = redactor
                let authInput = input
                let credentialTarget = selectedRoot + "|" + (input["credential_revision"]?.text ?? "") + "|" + (input["credential_host_identity"]?.text ?? "")
                let reply = try await self.core.request(method, timeout: method == "launch_game" || method == "performance_apply" || method == "performance_restore" ? 900 : 90, params: input) { [weak self] event in
                    Task { @MainActor in
                        guard let self, self.operationGeneration == generation else { return }
                        if method == "launch_game" { self.launchSession.consume(event) }
                        if event["kind"]?.text == "credential_status",
                           let role = event["credential_kind"]?.text.flatMap(CredentialKind.init(rawValue:)) {
                            if event["status"]?.text == "rejected" { self.credentials.reject(role) }
                            else if event["status"]?.text == "authenticated", let value = authInput[role.bridgeField]?.text {
                                await self.credentials.authenticated(role, value: value, target: credentialTarget)

                            }
                        }
                        if method == "run_network_diagnostics", let row = event["diagnostic"]?.object, let name = row["name"]?.text {
                            self.networkRows.removeAll { $0["name"]?.text == name }
                            self.networkRows.append(eventRedactor.diagnostic(row))
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
                if let boot = reply.result["guest_boot"]?.text { try self.credentials.bindGuest(boot) }
                for role in CredentialKind.allCases {
                    if reply.result[role.rawValue + "_password_verified"]?.boolean == true, let value = authInput[role.bridgeField]?.text {
                        await self.credentials.authenticated(role, value: value, target: credentialTarget)
                    }
                }
                if method == "read_configuration" { self.sshConfiguration = reply.result }
                if ["save_configuration", "restore_configuration"].contains(method) {
                    self.clearSessionCredentials()
                    self.guiSnapshots = [:]; self.sshConnectionTarget = [:]
                    self.networkPlan = [:]; self.networkIPv6 = [:]; self.networkRows = []
                    self.firstRunPlan = nil; self.firstRunReceipt = nil; self.firstRunState = .NotChecked
                    self.sshConfiguration = try await self.core.request("read_configuration").result
                }
                self.operationResult = reply.result
                if method == "read_performance" { self.performanceSnapshot = reply.result }
                if ["performance_read", "performance_apply", "performance_restore"].contains(method), self.runtimeRoot == selectedRoot {
                    self.performanceConfigurationState.acceptSnapshot(reply.result)
                }
                if ["performance_preview", "performance_restore_preview"].contains(method), self.runtimeRoot == selectedRoot { self.performanceConfigurationState.acceptPreview(reply.result) }
                if GUIAction(rawValue: method) != nil, self.runtimeRoot == selectedRoot { self.guiSnapshots[method] = reply.result }
                if method == "read_steamos_ipv6" || method == "apply_steamos_ipv6" {
                    self.networkIPv6 = reply.result
                    if let path = reply.result["backup_path"]?.text { self.networkBackup = path }
                    if self.networkBackup.isEmpty { self.networkBackup = reply.result["backups"]?.array.last?.object["path"]?.text ?? "" }
                    self.networkPlan = [:]
                }
                if method == "preview_steamos_ipv6" { self.networkPlan = reply.result; self.networkShowConfirmation = true }
                if method == "run_network_diagnostics" { self.networkRows = reply.result["items"]?.array.map(\.object) ?? [] }
                self.guiRecords[method]?.finish()
                self.recordGUIOperation(method)
                if method == "launch_game" || method == "observe_launch" { self.launchSession.complete(reply.result, at: reply.observedAt); self.recordLaunch() }
                self.appendLog(method + ": COMPLETED")
                if method == "launch_game", reply.result["game_process_detected"]?.boolean == true,
                   !Task.isCancelled, self.operationGeneration == generation,
                   self.operationSelection?.method == method {
                    self.operationSelection = nil
                }
            } catch {
                let failure = error as? ErrorState ?? ErrorState("PROTOCOL_ERROR", method: method)
                self.operationError = ErrorState(failure.code, method: failure.method, details: redactor.diagnostic(failure.details))
                if ["CREDENTIAL_SCOPE_CHANGED", "FX_ENTRY_MISMATCH", "FX_IDENTITY_UNVERIFIED", "FX_INSTANCE_MISMATCH"].contains(failure.code) { self.clearSessionCredentials() }
                if method.hasSuffix("steamos_ipv6") || method == "run_network_diagnostics" {
                    if method == "run_network_diagnostics" { self.networkDiagnosticError = self.operationError } else { self.networkError = self.operationError }
                    if let path = failure.details["backup_path"]?.text { self.networkBackup = path }
                    if method.hasSuffix("steamos_ipv6") {
                        self.networkIPv6 = ["status": .string("unknown"), "values": failure.details["actual_values"] ?? .object([:])]
                        self.networkPlan = [:]
                    }
                    if method == "run_network_diagnostics" {
                        for name in ["vm", "steam", "playfab", "udp"] where self.networkRows.first(where: { $0["name"]?.text == name })?["status"]?.text == "RUNNING" || self.networkRows.first(where: { $0["name"]?.text == name }) == nil {
                            self.networkRows.removeAll { $0["name"]?.text == name }
                            self.networkRows.append(NetworkDiagnosticsService.row(name, failure.code == "CANCELLED" ? .cancelled : failure.code == "TIMEOUT" ? .timeout : .fail, reason: failure.code))
                        }
                    }
                }
                if failure.code == "SUDO_AUTH_FAILED" { self.credentials.reject(.sudo) }
                if failure.code == "SSH_AUTH_FAILED" { self.credentials.reject(.ssh) }
                if method == "launch_game" || method == "observe_launch", let failure = self.operationError {
                    if method == "observe_launch" { self.launchSession = LaunchSession() }
                    self.launchSession.fail(failure)
                    self.recordLaunch()
                }
                self.guiRecords[method]?.finish(self.operationError)
                self.recordGUIOperation(method)
                if GUIAction(rawValue: method) != nil, ["AUTH_REQUIRED","SSH_AUTH_FAILED","SUDO_AUTH_FAILED","CREDENTIAL_SCOPE_CHANGED","CHANGE_CONFIRMATION_REQUIRED","RUNTIME_ROOT_REQUIRED"].contains(failure.code), self.operationSelection == nil {
                    self.operationSelection = NativeOperation(method: method)
                }
                self.appendLog(method + ": " + (self.operationError?.code ?? "UNKNOWN"))
            }
        }
    }
    func discardPerformancePreview() { performanceConfigurationState.preview = [:] }
    func previewPerformance(restore: Bool = false) {
        guard let revision = performanceConfiguration["revision"]?.text else { return }
        runOperation(restore ? "performance_restore_preview" : "performance_preview", params: [
            "expected_revision": .string(revision), "values": .object(editedPerformance)])
    }
    func confirmPerformance() {
        guard let plan = performancePreview["plan"]?.object,
              let token = performancePreview["token"]?.text,
              let revision = plan["revision"]?.text,
              let after = plan["after"] else { return }
        runOperation(plan["restore"]?.boolean == true ? "performance_restore" : "performance_apply", params: [
            "confirmed": .bool(true), "expected_revision": .string(revision), "values": after, "preview_token": .string(token)])
    }
    func perform(_ action: GUIAction) {
        if action == .game && networkDiagnosticRunning {
            guard !networkLaunchPending else { return }
            networkLaunchPending = true
            tasks.cancel()
            Task { @MainActor [weak self] in
                guard let self else { return }
                while self.tasks.busy { try? await Task.sleep(nanoseconds: 50_000_000) }
                guard self.networkLaunchPending else { return }
                self.networkLaunchPending = false
                self.perform(.game)
            }
            return
        }
        guard !tasks.busy else { return }
        operationError = nil; operationResult = [:]; operationEvents = []
        if action == .game { scanFX(openingLaunch: true); return }
        if runtimeRoot.isEmpty { operationSelection = NativeOperation(method: action.rawValue) }
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
    func prepareCredentials() async {
        guard !NativeLocalization.isolatedUXSmoke, let selected = fxSelection.selectedPath else { return }
        do {
            let binding = try await core.request("credential_target", timeout: 45, params: ["fx_path": .string(selected)])
            guard let revision = binding.result["revision"]?.text, let identity = binding.result["identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
            let target = runtimeRoot + "|" + revision + "|" + identity
            if let scope = credentials.scope, scope != target { clearSessionCredentials() }
            await credentials.prepare(for: target)
            try credentials.bindGuest(binding.result["guest_boot"]?.text)
        } catch { clearSessionCredentials(); appendLog("credential target unavailable") }
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
    func forgetSavedCredentials() { clearSessionCredentials() }
    func clearSessionCredentials() { credentials.clear(); SSHTransport.closeOwnedMasters(); firstRunFEX = [:]; firstRunFEXTicket = nil; firstRunFEXRestore = nil }
    func endSession() { networkLaunchPending = false; tasks.cancel(); clearSessionCredentials() }
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
        var snapshot: [String: [String: JSONValue]] = [:]
        var snapshotTime: String?
        var failures: [String: String] = [:]
        for method in ["handshake", "get_launcher_version", "get_system_info", "get_environment_status", "get_dependencies", "list_fx_versions", "get_logs", "get_legacy_catalog"] {
            do {
                try Task.checkCancellation()
                let scanParams: [String: JSONValue] = method == "list_fx_versions" ? ["selected_paths": .array(fxSelection.scanPaths), "runtime_root": .string(runtimeRoot)] : [:]
                let reply = try await core.request(method, params: scanParams)
                try validate(method, result: reply.result)
                snapshot[method] = reply.result
                snapshotTime = reply.observedAt
                appendLog("\(method): OK [\(reply.requestID)]")
            } catch is CancellationError {
                appendLog("load: CANCELLED")
                return
            } catch {
                let failure = error as? ErrorState ?? ErrorState("PROTOCOL_ERROR", method: method)
                failures[method] = failure.code
                appendLog("\(method): \(failure.code)")
            }
        }
        if let scan = snapshot["list_fx_versions"] { applyFXScan(scan) }
        results = snapshot
        observedAt = snapshotTime
        fieldErrors = failures
        hasLoaded = true
        if snapshot.isEmpty { self.error = ErrorState("CORE_UNAVAILABLE"); stale = true } else { stale = false }
    }
    private func validate(_ method: String, result: [String: JSONValue]) throws {
        let valid: Bool
        switch method {
        case "get_launcher_version": valid = result["version"]?.text != nil
        case "get_system_info": valid = ["os", "os_version", "arch", "native_runtime"].allSatisfy { result[$0]?.text != nil }
        case "get_environment_status": valid = result["status"]?.text == "unverified" && result["checks"] != nil
        case "get_dependencies": valid = result["items"] != nil
        case "list_fx_versions": valid = result["candidates"] != nil && result["scan_incomplete"]?.boolean != nil
        case "get_logs": valid = result["entries"] != nil && ["native_core_session", "bridge_process_session"].contains(result["source"]?.text ?? "")
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

@MainActor extension AppState {
    func clearNetworkState() { networkLaunchPending = false; networkIPv6 = [:]; networkRows = []; networkPlan = [:]; networkError = nil; networkDiagnosticError = nil; networkBackup = ""; networkShowConfirmation = false }
    func previewIPv6(_ enabled: Bool? = nil, restore: Bool = false) {
        var params: [String: JSONValue] = [:]
        if restore { guard !networkBackup.isEmpty else { return }; params["backup_path"] = .string(networkBackup) }
        else if let enabled { params["ipv6_enabled"] = .bool(enabled) }
        runOperation("preview_steamos_ipv6", params: params)
    }
    func applyIPv6Plan() {
        guard !networkPlan.isEmpty else { return }
        let plan = networkPlan
        networkShowConfirmation = false
        runOperation("apply_steamos_ipv6", params: ["confirmed": .bool(true), "network_plan": .object(plan)])
    }
}
