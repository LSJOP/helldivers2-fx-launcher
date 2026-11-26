import OSLog
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selection: Page? = .dashboard
    #if DEBUG
    // Only the isolated fixture host calls this. These values do not represent a real
    // scan, deployment, guest, or game launch; the host labels and disables its UI.
    func configureArtworkFixture(scenario: String, language: String, appearance: Appearance) {
        guard NativeLocalization.artworkPreviewAllowed else { return }
        languageCode = language == "zh-CN" ? "zh-CN" : "en"
        self.appearance = appearance
        if scenario == "completion" || scenario == "failure" {
            let root = "/ui-preview-fixture/FX.app"
            let boot = "ui-preview-fixture-boot"
            fxSelection.reconcile([["path": .string(root), "identity_valid": .bool(true), "structure": .string("metadata_valid")]], incomplete: false)
            runtimeRoot = root
            try? credentials.bindGuest(boot)
            let snapshot = DeploymentSnapshot(target: "fixture", boot: boot, revision: "fixture", fxVersion: "fixture", osVersion: "fixture", architecture: "aarch64", steamRunning: false, gameRunning: false, freeBytes: 0,
                facts: scenario == "failure" ? ["fex_status": "repair", "fex_diagnostic_reason": "RF_BUNDLE_PAYLOAD_UNAVAILABLE"] : [:], values: [:])
            let operations = ["fex", "proton", "steam", "game"].map { component in
                DeploymentOperation(id: component, component: component, currentVersion: ["fex", "proton"].contains(component) ? "verified" : "present", targetVersion: "fixture", changes: [:], permission: "", estimatedBytes: 0, needsRestart: false, backupLocation: "", rollback: "", verification: "", requirement: .REQUIRED, blocked: scenario == "failure" && component == "fex" ? "ARTIFACT_UNAVAILABLE" : nil)
            }
            firstRunPlan = DeploymentPlan(id: UUID(), profileID: "fixture", profileVersion: 1, snapshot: snapshot, operations: operations)
            if scenario == "failure" {
                firstRunState = .Failed
                environmentWorkflow = EnvironmentWorkflow(phase: .failed, completedSteps: 3,
                    failure: ErrorState("ARTIFACT_UNAVAILABLE", details: ["component": .string("fex"), "diagnostic_reason": .string("RF_BUNDLE_PAYLOAD_UNAVAILABLE")]),
                    evidence: ["fx_runtime_repair_attempted": .bool(true), "fx_runtime_resource_source": .string("bundle-first")])
            } else {
                firstRunState = .Completed
                environmentWorkflow = EnvironmentWorkflow(phase: .completed, completedSteps: 5)
            }
            selection = .setup
        } else if scenario == "fx" || scenario.hasPrefix("fx-") {
            let fixtures: [[String: JSONValue]] = [
                ["path": .string("/ui-preview-fixture/One/FX Steam Launcher.app"), "name": .string("FX Steam Launcher"), "version": .string("1.9.9"), "identity_valid": .bool(true), "structure": .string("metadata_valid")],
                ["path": .string("/ui-preview-fixture/Two/FX Steam Launcher.app"), "name": .string("FX Steam Launcher"), "version": .string("1.9.9"), "identity_valid": .bool(true), "structure": .string("metadata_valid")],
                ["path": .string("/ui-preview-fixture/Three/FX Steam Launcher.app"), "name": .string("FX Steam Launcher"), "version": .string("1.9.8"), "identity_valid": .bool(true), "structure": .string("metadata_valid")]
            ]
            let count = ["fx", "fx-switch"].contains(scenario) ? 3 : min(5, max(0, Int(scenario.dropFirst(3)) ?? 1))
            let additional: [[String: JSONValue]] = (4...5).map { index in
                ["path": .string("/ui-preview-fixture/Archive/\(index)/FX Steam Launcher.app"),
                 "name": .string("FX Steam Launcher Archive \(index)"), "version": .string("1.9.8"),
                 "identity_valid": .bool(true), "structure": .string("metadata_valid")]
            }
            let rows = Array((fixtures + additional).prefix(count))
            fxSelection.reconcile(rows, incomplete: false)
            fxSelection.select(rows.first?["path"]?.text)
            if scenario == "fx-loading", let target = fxSelection.selectedPath {
                let method = GUIAction.startFX.rawValue
                guiRecords[method] = GUIOperationRecord(method: method, target: target)
            }
            runtimeRoot = fxSelection.selectedPath ?? ""
            if scenario == "fx-switch", let path = rows.last?["path"]?.text { selectFX(path) }
            results["list_fx_versions"] = ["candidates": .array(rows.map(JSONValue.object)), "scan_incomplete": .bool(false)]
            selection = .dashboard
        } else if scenario == "launch" {
            environmentWorkflow = EnvironmentWorkflow(phase: .detecting, completedSteps: 2, launchesGame: true)
            selection = .dashboard
        }
    }
    #endif
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
    let credentials = SessionCredentialManager(store: NativeLocalization.isolatedUXSmoke ? nil : LocalCredentialStore.production())
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
        let started = ProcessInfo.processInfo.systemUptime
        workflowLog(generation, "\(method): started")
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
                    await self.credentials.prepare(for: target, savedTarget: binding.result["persistence_identity"]?.text)
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
                        if let raw = event["deployment_state"]?.text, DeploymentState(rawValue: raw) != nil {
                            self.workflowLog(generation, "\(method): \(raw)")
                        }
                        if event["kind"]?.text == "deployment_component", let component = event["component"]?.text,
                           ["fex", "proton", "steam", "tool", "launch", "vulkan"].contains(component),
                           let status = event["status"]?.text, ["running", "done", "failed", "deferred"].contains(status) {
                            self.workflowLog(generation, "\(component): \(status)", level: status == "failed" ? "ERROR" : "INFO")
                        }
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
                    if [.Completed, .NeedsConfiguration].contains(self.firstRunState) {
                        self.firstRunState = next.detectionState == .Ready ? .Completed : next.detectionState
                    }
                }
                if let value = reply.result["receipts"] { self.firstRunReceipts = try JSONDecoder().decode([DeploymentReceipt].self, from: JSONEncoder().encode(value)) }
                self.workflowLog(generation, "\(method): completed (\(Int(max(0, ProcessInfo.processInfo.systemUptime - started)))s)", level: "SUCCESS")
            } catch {
                self.firstRunEventGeneration = nil
                let code = (error as? ErrorState)?.code ?? (error as? CoreError)?.code ?? "DEPLOYMENT_FAILED"
                self.workflowLog(generation, "\(method): \(code) (\(Int(max(0, ProcessInfo.processInfo.systemUptime - started)))s)", level: "ERROR")
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
        if let destination = pendingEnvironmentDestination, fxSelection.selected != nil {
            pendingEnvironmentDestination = nil
            selection = destination == .game ? .dashboard : .setup
            startEnvironmentWorkflow(launchGame: destination == .game)
        }
    }
    func scanFX(manualPath: String? = nil, openingLaunch: Bool = false, workflow: EnvironmentWorkflowDestination? = nil) {
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
                if let destination = workflow ?? (openingLaunch ? .game : nil) {
                    if self.fxSelection.selected == nil {
                        self.pendingEnvironmentDestination = destination
                        self.selection = .fx
                    }
                    else {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            while self.tasks.busy { try? await Task.sleep(nanoseconds: 50_000_000) }
                            guard !Task.isCancelled else { return }
                            self.startEnvironmentWorkflow(launchGame: destination == .game)
                        }
                    }
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
    @Published var appearance = UserDefaults.standard.string(forKey: "NativeAppearance")
        .flatMap(Appearance.init(rawValue:)) ?? .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "NativeAppearance") }
    }
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
        workflowLog(generation, "\(method): \(logStatus("started"))")
        let selectedRoot = runtimeRoot
        let launchParameters = fxSelection.launchParameters(runtimeRoot: selectedRoot)
        var redactor = credentials.redactor
        if method == "run_network_diagnostics" { networkRows = []; networkDiagnosticError = nil }
        if method.hasSuffix("steamos_ipv6") { networkError = nil; if method != "apply_steamos_ipv6" { networkPlan = [:] } }
        if method == "launch_game" { launchSession.begin(root: selectedRoot, taskID: generation); recordLaunch() }
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
                    await self.credentials.prepare(for: target, savedTarget: binding.result["persistence_identity"]?.text)
                    if let boot = binding.result["guest_boot"]?.text { try self.credentials.bindGuest(boot) }
                    input.merge(try self.credentials.parameters(for: target)) { _, new in new }
                    input["credential_host_identity"] = .string(identity)
                    redactor = self.credentials.redactor
                    input["credential_revision"] = .string(revision)
                }
                let eventRedactor = redactor
                let authInput = input
                let credentialTarget = selectedRoot + "|" + (input["credential_revision"]?.text ?? "") + "|" + (input["credential_host_identity"]?.text ?? "")
                let operationTimeout: TimeInterval = method == "launch_game" ? 600 : (method == "performance_apply" || method == "performance_restore" ? 900 : 90)
                let reply = try await self.core.request(method, timeout: operationTimeout, params: input) { [weak self] event in
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
                        var logEvent = safeEvent
                        logEvent["id"] = .string(UUID().uuidString)
                        if method == "launch_game" { logEvent["message"] = .string("[\(generation.uuidString)] " + (safeEvent["message"]?.text ?? "")) }
                        self.runtimeLogs.append(logEvent)
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
                if method == "launch_game", ["AUTH_REQUIRED", "SSH_AUTH_FAILED", "SUDO_AUTH_FAILED"].contains(failure.code) {
                    self.launchCredentialKind = failure.code == "SUDO_AUTH_FAILED" ? "sudo_password" : failure.details["credential_kind"]?.text ?? "password"
                } else if GUIAction(rawValue: method) != nil, ["AUTH_REQUIRED","SSH_AUTH_FAILED","SUDO_AUTH_FAILED","CREDENTIAL_SCOPE_CHANGED","CHANGE_CONFIRMATION_REQUIRED","RUNTIME_ROOT_REQUIRED"].contains(failure.code), self.operationSelection == nil {
                    self.operationSelection = NativeOperation(method: method)
                }
            }
        }
    }
    @Published var launchCredentialKind: String?
    func resumeLaunchWithCredential(_ value: String, kind: String) {
        guard !value.isEmpty else { return }
        if kind == "sudo_password" { credentials.sudoPassword = value }
        else if kind == "passphrase" { credentials.passphrase = value }
        else {
            credentials.password = value
            if credentials.sudoPassword.isEmpty { credentials.useSSHPasswordForSudo() }
        }
        launchCredentialKind = nil
        Task { @MainActor [weak self] in
            guard let self else { return }
            while self.tasks.busy { try? await Task.sleep(nanoseconds: 50_000_000) }
            self.startEnvironmentWorkflow(launchGame: self.environmentWorkflow.phase == .failed ? self.environmentWorkflow.launchesGame : true)
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
        if action == .game {
            if fxSelection.selected != nil { startEnvironmentWorkflow(launchGame: true) }
            else { scanFX(openingLaunch: true) }
            return
        }
        if runtimeRoot.isEmpty { operationSelection = NativeOperation(method: action.rawValue) }
        else if action.needsReview { pendingAction = action }
        else { runOperation(action.rawValue, params: ["confirmed": .bool(true)]) }
    }
    var latestGUIEvidence: [String: JSONValue] {
        if environmentWorkflow.phase != .idle { return environmentWorkflow.evidence }
        return guiRecords.values.filter { $0.target == runtimeRoot && $0.status == .succeeded && guiSnapshots[$0.method] != nil }
            .max { $0.startedAt < $1.startedAt }.flatMap { guiSnapshots[$0.method] } ?? [:]
    }
    func confirmPendingAction(_ action: GUIAction) {
        pendingAction = nil
        runOperation(action.rawValue, params: ["confirmed": .bool(true)])
    }
    private func recordGUIOperation(_ method: String) {
        guard let record = guiRecords[method] else { return }
        let details: [String: JSONValue] = ["task_id": .string(operationGeneration.uuidString), "operation": .string(method), "started_at": .string(ISO8601DateFormatter().string(from: record.startedAt)),
            "ended_at": .string(ISO8601DateFormatter().string(from: record.endedAt ?? Date())), "status": .string(record.status.rawValue),
            "error_code": .string(record.error?.code ?? "none")]
        if let data = try? JSONEncoder().encode(JSONValue.object(details)), let text = String(data: data, encoding: .utf8) {
            runtimeLogs.append(["id": .string(UUID().uuidString), "at": .string(ISO8601DateFormatter().string(from: Date())), "source": .string("Native action"), "level": .string(record.error == nil ? "INFO" : "ERROR"), "message": .string(credentials.redactor.text(text))])
            if runtimeLogs.count > 500 { runtimeLogs.removeFirst(runtimeLogs.count - 500) }
        }
    }
    private var pendingEnvironmentDestination: EnvironmentWorkflowDestination?
    @Published var environmentWorkflow = EnvironmentWorkflow()
    private var workflowPhaseStarted = ProcessInfo.processInfo.systemUptime
    private var workflowStarted = ProcessInfo.processInfo.systemUptime
    private var workflowEventIDs = Set<String>()
    private var workflowStageStarted: [String: TimeInterval] = [:]

    private func logStatus(_ value: String) -> String {
        switch value {
        case "running": return t("ui.157")
        case "failed": return t("ui.125")
        case "waiting": return t("ui.logs.waiting")
        case "deferred": return t("ui.logs.deferred")
        case "done", "passed", "completed": return t("ui.logs.completed")
        case "started": return t("ui.logs.started")
        default: return value
        }
    }

    private static let launchLogger = Logger(subsystem: "com.lsjop.helldivers2fx.native.phase1", category: "launch")

    private func workflowLog(_ id: UUID, _ message: String, level: String = "INFO", at: String? = nil) {
        let safe = credentials.redactor.text(message)
        if environmentWorkflow.launchesGame {
            Self.launchLogger.notice("task=\(id.uuidString, privacy: .public) level=\(level, privacy: .public) \(safe, privacy: .private)")
        }
        runtimeLogs.append(["id": .string(UUID().uuidString), "at": .string(at ?? ISO8601DateFormatter().string(from: Date())),
                            "source": .string("Workflow"), "level": .string(level),
                            "message": .string("[\(id.uuidString)] " + safe)])
        if runtimeLogs.count > 500 { runtimeLogs.removeFirst(runtimeLogs.count - 500) }
    }
    private func workflowPhase(_ phase: EnvironmentWorkflowPhase) {
        let now = ProcessInfo.processInfo.systemUptime
        let id = environmentWorkflow.taskID
        workflowLog(id, "\(t(environmentWorkflow.phase.titleKey)): \(logStatus("completed")) (\(Int(max(0, now - workflowPhaseStarted)))s)")
        environmentWorkflow.archiveComponent = nil
        environmentWorkflow.archivePhase = nil
        environmentWorkflow.phase = phase
        workflowPhaseStarted = now
        workflowLog(id, "\(t(phase.titleKey)): \(logStatus("started"))")
    }
    func steamRuntimePhaseTitle(_ phase: String) -> String {
        switch phase {
        case "login": return t("ui.steamRuntime.login")
        case "requesting": return t("ui.steamRuntime.requesting")
        case "downloading": return t("ui.steamRuntime.downloading")
        case "installing": return t("ui.steamRuntime.installing")
        case "verifying": return t("ui.steamRuntime.verifying")
        case "ready": return t("ui.steamRuntime.ready")
        default: return t("ui.steamRuntime.checking")
        }
    }
    private func workflowEvent(_ event: [String: JSONValue], taskID: UUID) {
        guard environmentWorkflow.taskID == taskID else { return }
        let request = event["request_id"]?.text ?? ""
        let sequence = event["sequence"]?.integer ?? -1
        let key = request + ":" + String(sequence)
        guard !request.isEmpty, sequence >= 0, workflowEventIDs.insert(key).inserted else { return }
        if workflowEventIDs.count > 1000 { workflowEventIDs.removeAll(keepingCapacity: true); workflowEventIDs.insert(key) }
        let at = event["at"]?.text
        if let raw = event["stage"]?.text, let stage = LaunchStage(rawValue: raw),
           let status = event["status"]?.text, ["running", "waiting", "done", "passed", "failed"].contains(status) {
            Self.launchLogger.notice("task=\(taskID.uuidString, privacy: .public) stage=\(raw, privacy: .public) status=\(status, privacy: .public)")
            let now = ProcessInfo.processInfo.systemUptime
            let started = workflowStageStarted[raw]
            if status == "running", started == nil { workflowStageStarted[raw] = now }
            let elapsed = (status == "done" || status == "passed" || status == "failed") && started != nil
                ? " (\(Int(max(0, now - started!)))s)" : ""
            if status == "done" || status == "passed" || status == "failed" { workflowStageStarted.removeValue(forKey: raw) }
            workflowLog(taskID, "\(stage.title(languageCode)): \(logStatus(status))\(elapsed)", level: status == "failed" ? "ERROR" : "INFO", at: at)
        } else if event["kind"]?.text == "steam_runtime_stage", environmentWorkflow.phase == .deploying,
                  let phase = event["runtime_phase"]?.text,
                  ["checking", "login", "requesting", "downloading", "installing", "verifying", "ready"].contains(phase) {
            environmentWorkflow.archiveComponent = "steam-runtime"
            environmentWorkflow.archivePhase = phase
            workflowLog(taskID, steamRuntimePhaseTitle(phase), at: at)
        } else if event["kind"]?.text == "bundle_archive_stage", environmentWorkflow.phase == .deploying,
                  let component = event["component"]?.text, component == "Proton-JE",
                  let phase = event["archive_phase"]?.text, ["sftp", "install", "finished"].contains(phase) {
            environmentWorkflow.archiveComponent = phase == "finished" ? nil : component
            environmentWorkflow.archivePhase = phase == "finished" ? nil : phase
        } else if event["kind"]?.text == "deployment_component", let component = event["component"]?.text,
                  ["fex", "proton", "steam", "tool", "launch", "vulkan"].contains(component),
                  let status = event["status"]?.text, ["running", "done", "failed", "deferred"].contains(status) {
            let key = "component:" + component
            let now = ProcessInfo.processInfo.systemUptime
            let start = workflowStageStarted[key]
            if status == "running" { workflowStageStarted[key] = now }
            let elapsed = status != "running" && start != nil ? " (\(Int(max(0, now - start!)))s)" : ""
            if status != "running" { workflowStageStarted.removeValue(forKey: key) }
            workflowLog(taskID, "\(component): \(logStatus(status))\(elapsed)", level: status == "failed" ? "ERROR" : "INFO", at: at)
        } else if let raw = event["deployment_state"]?.text, let stage = DeploymentState(rawValue: raw) {
            workflowLog(taskID, "FX runtime / Proton / Steam: \(stage.rawValue)", at: at)
        } else if event["kind"]?.text == "credential_status", event["status"]?.text == "authenticated" {
            workflowLog(taskID, "SSH / sudo: authenticated", at: at)
        } else if event["kind"]?.text == "launch_request", let success = event["command_succeeded"]?.boolean {
            workflowLog(taskID, t(success ? "ui.logs.commandSucceeded" : "ui.logs.alreadyRunning"), at: at)
        }
    }
    func startEnvironmentWorkflow(launchGame: Bool) {
        guard !tasks.busy else { return }
        guard fxSelection.selected != nil else {
            scanFX(workflow: launchGame ? .game : .setup)
            return
        }
        environmentWorkflow = EnvironmentWorkflow(phase: .startingFX, launchesGame: launchGame)
        let taskID = environmentWorkflow.taskID
        workflowStarted = ProcessInfo.processInfo.systemUptime; workflowPhaseStarted = workflowStarted
        workflowEventIDs.removeAll(); workflowStageStarted.removeAll()
        workflowLog(taskID, "\(t(launchGame ? "ui.176" : "ui.workflow.result")): \(logStatus("started"))")
        workflowLog(taskID, "\(t(EnvironmentWorkflowPhase.startingFX.titleKey)): \(logStatus("started"))")
        firstRunPlan = nil
        if launchGame { launchSession = LaunchSession() }
        let root = runtimeRoot
        let launch = fxSelection.launchParameters(runtimeRoot: root)
        tasks.start { [weak self] in
            guard let self else { return }
            do {
                var input = launch
                input["runtime_root"] = .string(root)
                input["confirmed"] = .bool(true)
                let fx = try await self.core.request("start_fx", timeout: 180, params: input)
                self.environmentWorkflow.evidence = fx.result
                try Task.checkCancellation()
                self.environmentWorkflow.completedSteps = 1
                self.workflowPhase(.connecting)
                let binding = try await self.core.request("credential_target", timeout: 45, params: launch)
                guard let revision = binding.result["revision"]?.text,
                      let identity = binding.result["identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                let target = root + "|" + revision + "|" + identity
                if let scope = self.credentials.scope, scope != target { self.clearSessionCredentials() }
                await self.credentials.prepare(for: target, savedTarget: binding.result["persistence_identity"]?.text)
                if self.credentials.sudoPassword.isEmpty { self.credentials.useSSHPasswordForSudo() }
                input.merge(try self.credentials.parameters(for: target)) { _, value in value }
                input["credential_revision"] = .string(revision)
                input["credential_host_identity"] = .string(identity)
                let connected = try await self.core.request("test_ssh", timeout: 90, params: input)
                guard let boot = connected.result["guest_boot"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                try self.credentials.bindGuest(boot)
                self.environmentWorkflow.evidence["ssh_connected"] = .bool(true)
                self.environmentWorkflow.evidence["guest_ready"] = .bool(true)
                if connected.result["ssh_password_verified"]?.boolean == true, let password = input["password"]?.text {
                    await self.credentials.authenticated(.ssh, value: password, target: target)
                }
                self.environmentWorkflow.completedSteps = 2
                self.workflowPhase(.detecting)
                var detected = try await self.core.request("first_run_detect", timeout: 240, params: input)
                guard var raw = detected.result["plan"] else { throw ErrorState("PROTOCOL_ERROR") }
                var plan = try JSONDecoder().decode(DeploymentPlan.self, from: JSONEncoder().encode(raw))
                let repairableFXReasons: Set<String> = [
                    "FEX_MISSING", "FEX_NOT_EXECUTABLE", "FEX_ARCHITECTURE",
                    "FEX_INTEGRATION_MISSING", "FEX_CHANGED", "FEX_INTEGRITY_FAILED",
                    "FEX_RUNTIME_FAILED", "FEX_DEPENDENCY_FAILED", "FEX_LOCAL_RUNTIME_MISSING",
                    "FEX_KNOWN_LAUNCH_INCOMPATIBILITY", "FEX_PROTON_INTEGRATED_UNVERIFIED",
                    "STEAM_RUNTIME_INCOMPATIBLE"
                ]
                if let repair = plan.operations.first(where: { $0.component == "fex" })?.blocked,
                   repairableFXReasons.contains(repair) {
                    self.firstRunPlan = plan
                    self.workflowPhase(.deploying)
                    self.workflowLog(taskID, "FX runtime: automatic repair started")
                    self.environmentWorkflow.evidence["fx_runtime_repair_attempted"] = .bool(true)
                    self.environmentWorkflow.evidence["fx_runtime_resource_source"] = .string("bundle-first")
                    input["credential_guest_boot"] = .string(boot)
                    let repairCredentials = input
                    let repaired = try await self.core.request("first_run_fex_repair", timeout: 6500, params: input) { [weak self] event in
                        if event["kind"]?.text == "credential_status", event["status"]?.text == "authenticated",
                           let role = event["credential_kind"]?.text.flatMap(CredentialKind.init(rawValue:)),
                           let value = repairCredentials[role.bridgeField]?.text {
                            Task { @MainActor in await self?.credentials.authenticated(role, value: value, target: target) }
                        }
                        Task { @MainActor in
                            guard let self, self.environmentWorkflow.taskID == taskID else { return }
                            self.workflowEvent(event, taskID: taskID)
                        }
                    }
                    self.environmentWorkflow.evidence["fx_runtime_repair_attempted"] = repaired.result["repair_attempted"] ?? .bool(true)
                    self.environmentWorkflow.evidence["fx_runtime_resource_source"] = repaired.result["repair_source"] ?? .string("unknown")
                    self.environmentWorkflow.evidence["fx_runtime_verification"] = repaired.result["verification"] ?? .null
                    self.workflowLog(taskID, "FX runtime: automatic repair verified")
                    self.workflowPhase(.detecting)
                    detected = try await self.core.request("first_run_detect", timeout: 240, params: input)
                    guard let refreshed = detected.result["plan"] else { throw ErrorState("PROTOCOL_ERROR") }
                    raw = refreshed
                    plan = try JSONDecoder().decode(DeploymentPlan.self, from: JSONEncoder().encode(raw))
                }
                self.firstRunPlan = plan
                for component in ["fex", "proton", "steam", "game"] {
                    if let operation = plan.operations.first(where: { $0.component == component }) {
                    self.workflowLog(taskID, "\(component == "fex" ? "FX runtime" : component): \(operation.detectionPassed ? "verified" : "unverified")")
                    }
                }
                self.environmentWorkflow.completedSteps = 3
                if let blocked = plan.operations.first(where: { $0.component == "fex" && $0.blocked != nil }) {
                    throw ErrorState(blocked.blocked ?? "FEX_RUNTIME_FAILED")
                }
                self.environmentWorkflow.evidence["steam_running"] = .bool(plan.snapshot.steamRunning)
                self.workflowPhase(.deploying)
                if !plan.executable.isEmpty {
                    input["deployment_plan"] = raw
                    input["approved_steps"] = .array(plan.executable.map { .string($0.id) })
                    input["restart_vm_approved"] = .bool(true)
                    let deploymentCredentials = input
                    let deployed = try await self.core.request("first_run_deploy", timeout: 1500, params: input) { [weak self] event in
                        if event["kind"]?.text == "credential_status", event["status"]?.text == "authenticated",
                           let role = event["credential_kind"]?.text.flatMap(CredentialKind.init(rawValue:)),
                           let value = deploymentCredentials[role.bridgeField]?.text {
                            Task { @MainActor in await self?.credentials.authenticated(role, value: value, target: target) }
                        }
                        Task { @MainActor in
                            guard let self, self.environmentWorkflow.taskID == taskID else { return }
                            self.workflowEvent(event, taskID: taskID)
                            if self.environmentWorkflow.phase == .deploying, let stage = event["deployment_state"]?.text, DeploymentState(rawValue: stage) != nil {
                                self.environmentWorkflow.deploymentStage = stage
                            }
                        }
                    }
                    if let receipt = deployed.result["receipt"] {
                        let record = try JSONDecoder().decode(DeploymentReceipt.self, from: JSONEncoder().encode(receipt))
                        self.firstRunReceipt = record
                        guard [.Completed, .NeedsConfiguration].contains(record.state) else {
                            throw ErrorState(record.failure ?? "DEPLOYMENT_FAILED")
                        }
                    } else { throw ErrorState("PROTOCOL_ERROR") }
                    if let transition = deployed.result["reboot_transition"]?.object,
                       let old = transition["from"]?.text, let new = transition["to"]?.text,
                       let identity = transition["host_identity"]?.text {
                        let rebound = root + "|" + revision + "|" + identity
                        try self.credentials.acceptExpectedReboot(from: old, to: new, target: target, reboundTarget: rebound)
                        input["credential_host_identity"] = .string(identity)
                        input["credential_guest_boot"] = .string(new)
                    }
                }
                self.environmentWorkflow.completedSteps = 4
                self.workflowPhase(.verifying)
                try Task.checkCancellation()
                let verified = try await self.core.request("first_run_detect", timeout: 240, params: input)
                guard let raw = verified.result["plan"] else { throw ErrorState("PROTOCOL_ERROR") }
                let fresh = try JSONDecoder().decode(DeploymentPlan.self, from: JSONEncoder().encode(raw))
                self.firstRunPlan = fresh
                if let pending = fresh.executable.first {
                    throw ErrorState("VERIFY_FAILED", details: ["component": .string(pending.component)])
                }
                if launchGame, let blocked = fresh.operations.first(where: {
                    ["fex", "proton", "tool", "launch", "steam", "game"].contains($0.component) && $0.blocked != nil
                }) { throw ErrorState(blocked.blocked ?? "VERIFY_FAILED", details: ["component": .string(blocked.component)]) }
                if !launchGame, let unverified = fresh.firstUnverifiedSetupOperation {
                    throw ErrorState(unverified.blocked ?? "VERIFY_FAILED", details: ["component": .string(unverified.component)])
                }
                self.firstRunState = .Completed
                self.environmentWorkflow.completedSteps = 5
                if launchGame {
                    self.workflowPhase(.launching)
                    self.launchSession.begin(root: root, taskID: taskID)
                    let reply = try await self.core.request("launch_game", timeout: 600, params: input) { [weak self] event in
                        Task { @MainActor in
                            guard let self, self.environmentWorkflow.taskID == taskID else { return }
                            self.launchSession.consume(event)
                            self.workflowEvent(event, taskID: taskID)
                        }
                    }
                    self.launchSession.complete(reply.result, at: reply.observedAt)
                    self.environmentWorkflow.evidence.merge(reply.result) { _, value in value }
                    self.recordLaunch()
                    guard reply.result["game_process_detected"]?.boolean == true else { throw ErrorState("GAME_LAUNCH_FAILED") }
                    self.environmentWorkflow.completedSteps = 6
                }
                self.workflowLog(taskID, "\(self.t(self.environmentWorkflow.phase.titleKey)): \(self.logStatus("completed")) (\(Int(max(0, ProcessInfo.processInfo.systemUptime - self.workflowPhaseStarted)))s)", level: "SUCCESS")
                self.environmentWorkflow.phase = .completed
                self.workflowLog(taskID, "\(self.t(launchGame ? "ui.176" : "ui.workflow.result")): \(self.logStatus("completed")) (\(Int(max(0, ProcessInfo.processInfo.systemUptime - self.workflowStarted)))s)", level: "SUCCESS")
                if launchGame { self.workflowLog(taskID, self.t("ui.logs.processOnly")) }
                self.appendLog("environment_workflow: COMPLETED")
            } catch {
                let failure = error as? ErrorState ?? ErrorState(error is CancellationError ? "CANCELLED" : "PROTOCOL_ERROR")
                self.environmentWorkflow.failure = ErrorState(failure.code, details: self.credentials.redactor.diagnostic(failure.details))
                let reason = self.environmentWorkflow.failure?.details["reason"]?.text.map { String($0.prefix(300)) }
                let exitCode = failure.details["steam_exit_code"]?.integer ?? failure.details["exit_code"]?.integer
                let exitNote = exitCode.map { " / exit_code=" + String($0) } ?? ""
                if launchGame {
                    Self.launchLogger.error("task=\(taskID.uuidString, privacy: .public) failure=\(failure.code, privacy: .public) exit_code=\(exitCode ?? -1, privacy: .public)")
                }
                self.workflowLog(taskID, "\(self.t(self.environmentWorkflow.phase.titleKey)): \(failure.code)\(reason.map { " / " + $0 } ?? "")\(exitNote) (\(Int(max(0, ProcessInfo.processInfo.systemUptime - self.workflowPhaseStarted)))s)", level: "ERROR")
                self.environmentWorkflow.phase = failure.code == "CANCELLED" ? .cancelled : .failed
                self.workflowLog(taskID, "\(self.environmentWorkflow.phase.rawValue): \(failure.code) (\(Int(max(0, ProcessInfo.processInfo.systemUptime - self.workflowStarted)))s)", level: "ERROR")
                self.appendLog("environment_workflow: " + failure.code)
                self.firstRunState = .Failed
                if self.launchSession.running { self.launchSession.fail(failure); self.recordLaunch() }
                if ["AUTH_REQUIRED", "SSH_AUTH_FAILED", "SUDO_AUTH_FAILED"].contains(failure.code) {
                    self.launchCredentialKind = failure.code == "SUDO_AUTH_FAILED" || ["sudo", "sudo_password"].contains(failure.details["credential_kind"]?.text ?? "") ? CredentialKind.sudo.bridgeField : CredentialKind.ssh.bridgeField
                }
            }
        }
    }
    @Published var credentialConnectionStatus = "idle"
    @Published var credentialConnectionError: ErrorState?
    func clearCurrentCredentials() {
        guard !tasks.busy else { return }
        tasks.start { [weak self] in
            guard let self else { return }
            await self.prepareCredentials()
            guard self.credentials.scope != nil, self.credentials.hasPersistenceTarget else {
                self.credentialConnectionError = ErrorState("FX_IDENTITY_UNVERIFIED")
                self.credentialConnectionStatus = "failed"
                return
            }
            self.forgetSavedCredentials()
        }
    }
    func connectCredential(_ candidate: String) {
        guard !tasks.busy else { return }
        credentialConnectionStatus = "connecting"
        credentialConnectionError = nil
        let root = runtimeRoot
        let launch = fxSelection.launchParameters(runtimeRoot: root)
        tasks.start { [weak self] in
            guard let self else { return }
            var secret = candidate
            do {
                let fx = try await self.core.request("check_fx_state", timeout: 45, params: launch)
                guard fx.result["fx_host_running"]?.boolean == true else { throw ErrorState("FX_NOT_RUNNING") }
                let metadata = try await self.core.request("read_configuration")
                guard let revision = metadata.result["revision"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                let binding = try await self.core.request("credential_target", timeout: 45, params: launch)
                guard let identity = binding.result["identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
                let target = root + "|" + revision + "|" + identity
                if let scope = self.credentials.scope, scope != target { self.clearSessionCredentials() }
                await self.credentials.prepare(for: target, savedTarget: binding.result["persistence_identity"]?.text)
                if secret.isEmpty { secret = self.credentials.password }
                guard !secret.isEmpty else { throw ErrorState("AUTH_REQUIRED") }
                var input = launch
                input["runtime_root"] = .string(root)
                input["confirmed"] = .bool(true)
                input["password"] = .string(secret)
                input["credential_revision"] = .string(revision)
                input["credential_host_identity"] = .string(identity)
                let reply = try await self.core.request("test_ssh", timeout: 90, params: input)
                guard reply.result["ssh_password_verified"]?.boolean == true,
                      let boot = reply.result["guest_boot"]?.text else { throw ErrorState("AUTH_REQUIRED") }
                try self.credentials.bindGuest(boot)
                await self.credentials.acceptSharedPassword(secret, target: target)
                self.credentialConnectionStatus = "connected"
            } catch {
                let failure = error as? ErrorState ?? ErrorState("PROTOCOL_ERROR")
                self.credentialConnectionError = ErrorState(failure.code)
                self.credentialConnectionStatus = "failed"
            }
        }
    }
    func prepareCredentials() async {
        guard !NativeLocalization.isolatedUXSmoke, let selected = fxSelection.selectedPath else { return }
        do {
            let binding = try await core.request("credential_target", timeout: 45, params: ["fx_path": .string(selected)])
            guard let revision = binding.result["revision"]?.text, let identity = binding.result["identity"]?.text else { throw ErrorState("PROTOCOL_ERROR") }
            let target = runtimeRoot + "|" + revision + "|" + identity
            if let scope = credentials.scope, scope != target { clearSessionCredentials() }
            await credentials.prepare(for: target, savedTarget: binding.result["persistence_identity"]?.text)
            if let boot = binding.result["guest_boot"]?.text { try credentials.bindGuest(boot) }
        } catch { clearSessionCredentials(); appendLog("credential target unavailable") }
    }
    private func recordLaunch() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        let record = launchSession.diagnostic(appVersion: version + " (" + build + ")")
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let bytes = try? encoder.encode(JSONValue.object(record)), let text = String(data: bytes, encoding: .utf8) else { return }
        runtimeLogs.append(["id": .string(UUID().uuidString), "at": .string(ISO8601DateFormatter().string(from: Date())), "source": .string("Native launch"),
                            "level": .string(launchSession.failure == nil ? "INFO" : "ERROR"),
                            "message": .string(credentials.redactor.text(text))])
        if runtimeLogs.count > 500 { runtimeLogs.removeFirst(runtimeLogs.count - 500) }
    }
    func firstRunDiagnosticReport() -> String {
        let info = Bundle.main.infoDictionary ?? [:]
        let product = languageCode == "zh-CN" ? "绝地潜兵 2 FX 启动器" : languageCode == "zh-TW" ? "絕地潛兵 2 FX 啟動器" : "HELLDIVERS 2 FX Launcher"
        let snapshot = firstRunPlan?.snapshot
        let failure = environmentWorkflow.failure
        let operations = firstRunPlan?.operations.map { operation in
            let name = operation.component == "fex" ? "FX runtime" : operation.component
            let status = operation.blocked ?? (firstRunPlan?.setupObservationVerified(operation) == true ? "PASS" : operation.changes.isEmpty ? "UNVERIFIED" : "REPAIR_REQUIRED")
            return "- \(name): \(status)"
        }.joined(separator: "\n") ?? "- unavailable"
        let details = failure.map { $0.details.isEmpty ? "none" : CoreJSON.encode(.object($0.details)) } ?? "none"
        let source = environmentWorkflow.evidence["fx_runtime_resource_source"]?.text
            ?? snapshot?.facts["fex_source_type"] ?? "unknown"
        let report = """
        \(product)
        App version: \(info["CFBundleShortVersionString"] as? String ?? "unknown") (\(info["CFBundleVersion"] as? String ?? "unknown"))
        FX Steam Launcher version: \(snapshot?.fxVersion ?? fxVersion)
        SteamOS version: \(snapshot?.osVersion ?? "unknown")
        Failed stage: \(environmentWorkflow.phase.rawValue)
        Internal error code: \(failure?.code ?? firstRunFailure ?? "none")
        Actual reason: \(snapshot?.facts["fex_diagnostic_reason"] ?? failure?.details["diagnostic_reason"]?.text ?? "unknown")
        Component checks:
        \(operations)
        Automatic repair attempted: \(environmentWorkflow.evidence["fx_runtime_repair_attempted"]?.boolean == true ? "yes" : "no")
        Resource source: \(source)
        Verification: \(CoreJSON.encode(environmentWorkflow.evidence["fx_runtime_verification"] ?? .null))
        FX runtime executable SHA-256: \(snapshot?.facts["fex_executable_sha256"] ?? "unknown")
        FX runtime tree SHA-256: \(snapshot?.facts["fex_tree"] ?? "unknown")
        Permission diagnostic: \(snapshot?.facts["fex_diagnostic_reason"] ?? "unknown")
        Technical details: \(details)
        """
        return CoreRedaction.scrub(credentials.redactor.text(report))
    }
    func confirmMainMenu() { launchSession.confirmMainMenu(); recordLaunch() }
    func confirmSinglePlayer() { launchSession.confirmSinglePlayer(); recordLaunch() }
    func forgetSavedCredentials() { credentials.forgetSaved(); SSHTransport.closeOwnedMasters() }
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
        let liveLogs = runtimeLogs.map { ($0["at"]?.text ?? "") + "  " + ($0["message"]?.text ?? "") }
        return credentials.redactor.text((sessionLogs + bridgeLogs + liveLogs).sorted().joined(separator: "\n"))
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
