import SwiftUI

struct FirstRunSetupView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @ObservedObject var credentials: SessionCredentialManager
    @State private var authorize = false
    @State private var fexAction: String?
    @State private var recoverID: UUID?
    @State private var recoverySelection = Set<String>()
    private var plan: DeploymentPlan? { state.firstRunPlan }
    @ViewBuilder private var fexButtons: some View {
        Button(state.t("ui.fex.audit")) { state.firstRunAction("first_run_fex_audit") }
        Button(state.t("ui.fex.build")) { fexAction = "build" }
        Button(state.t("ui.fex.install")) { fexAction = "install" }
            .disabled(state.firstRunFEX["ready"]?.boolean != true || state.firstRunFEXTicket == nil)
        Button(state.t("ui.fex.recover")) { fexAction = "recover" }
            .disabled(state.firstRunFEXRestore == nil)
    }
    private func statusKey(_ operation: DeploymentOperation) -> String {
        switch operation.observation {
        case .advisory: return "ui.setup.status.advisory"
        case .passed: return "ui.net.pass"
        case .found: return "ui.setup.status.found"
        case .unverified: return "ui.368"
        case .blocked: return "ui.setup.blocked"
        case .unchanged: return "ui.setup.skip"
        case .change: return "ui.setup.change"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.setup.title"))
            TacticalPanel(number: "", title: state.t("ui.workflow.environment"), symbol: "checkmark.shield") {
                TacticalInfoRow(title: "FX", value: state.t(state.fxSelection.selected != nil ? "ui.219" : "ui.210"))
                TacticalInfoRow(title: "SteamOS", value: state.t(state.credentials.guestBoot != nil ? "ui.credentials.status.connected" : "ui.credentials.status.idle"))
                TacticalInfoRow(title: state.t("ui.135"), value: state.t(state.firstRunState == .Completed ? "ui.workflow.completed" : "ui.workflow.idle"))
            }
            TacticalPanel(number: "", title: state.t("ui.workflow.configure"), symbol: "wrench.and.screwdriver") {
                TacticalButton(title: state.t("ui.workflow.begin"), symbol: "play.fill", primary: true, disabledReason: tasks.busy ? state.t("ui.014") : nil) {
                    state.startEnvironmentWorkflow(launchGame: false)
                }
            }
            EnvironmentWorkflowProgressView(state: state, tasks: tasks, showIdle: true)
            DisclosureGroup(state.t("ui.workflow.advanced")) {
            TacticalPanel(number: "1", title: state.t("ui.setup.fx"), symbol: "shippingbox") {
                HStack {
                    Button(state.t("ui.fx.rescan")) { state.scanFX() }
                    Button(state.t("ui.setup.choose")) { state.selection = .fx }
                }
                Text(state.fxVersion + " · " + (state.fxSelection.selectedPath ?? state.t("ui.368"))).textSelection(.enabled)
                Text(plan?.snapshot.facts["os_version"] ?? state.t("ui.368"))
            }
            TacticalPanel(number: "2", title: state.t("ui.setup.connect"), symbol: "key") {
                SecureField(state.t("ui.305"), text: $credentials.password)
                SecureField(state.t("ui.304"), text: $credentials.sudoPassword)
                Button(state.t("ui.credentials.useSSHForSudo")) { credentials.useSSHPasswordForSudo() }
                    .disabled(credentials.password.isEmpty || tasks.busy)
                Text(state.t("ui.setup.credentials")).font(.caption)
                HStack {
                    Button(state.t("ui.setup.detect")) { state.firstRunAction("first_run_detect") }
                    Button(state.t("ui.setup.sudo")) { state.operationSelection = NativeOperation(method: "test_guest_sudo") }
                }
                if let snapshot = plan?.snapshot {
                    Text(state.t("ui.setup.identity") + " · " + String(snapshot.boot.prefix(8)) + " · " + snapshot.architecture)
                }
            }
            TacticalPanel(number: "FEX", title: state.t("ui.fex.title"), symbol: "shippingbox") {
                Text(state.t("ui.fex.scope")).font(.caption)
                ViewThatFits(in: .horizontal) {
                    HStack { fexButtons }
                    VStack(alignment: .leading) { fexButtons }
                }
                if !state.firstRunFEX.isEmpty {
                    TacticalStatusBadge(text: state.t(state.firstRunFEX["recovered"]?.boolean == true ? "ui.integrated.015" : state.firstRunFEX["ready"]?.boolean == true || state.firstRunFEX["verified"]?.boolean == true ? "ui.220" : "ui.368"))
                    if let hash = state.firstRunFEX["executable_sha256"]?.text, !hash.isEmpty, state.firstRunFEX["ready"]?.boolean != true {
                        Text(state.t("ui.fex.pendingReview")).font(.caption).foregroundStyle(.orange)
                    }
                    DisclosureGroup(state.t("ui.setup.details")) {
                        Text(verbatim: CoreJSON.encode(.object(state.firstRunFEX))).font(TacticalTypography.log).textSelection(.enabled)
                    }
                }
            }
            if let plan {
                TacticalPanel(number: "3–4", title: state.t("ui.setup.plan"), symbol: "list.bullet.clipboard") {
                    Text(plan.profileID + " / " + String(plan.profileVersion)).font(.caption.monospaced())
                    ForEach(plan.operations) { operation in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(state.t("ui.setup.component." + operation.component)).font(.headline)
                                Spacer()
                                Text(state.t(statusKey(operation)))
                                    .foregroundStyle(operation.detectionPassed ? .green : operation.warning ? .orange : .secondary)
                            }
                            Text(operation.component == "proton" && operation.detectionPassed ? operation.targetVersion : operation.changes.isEmpty ? operation.currentVersion : operation.currentVersion + " → " + operation.targetVersion).font(.caption.monospaced())
                            if operation.component == "fex", operation.blocked != nil { Text(state.t("ui.setup.artifactUnavailable")).font(.caption) }
                            if operation.blocked == "COMPONENT_CONFLICT" { Text(state.t("ui.setup.blocked") + " / COMPONENT_CONFLICT").font(.caption) }
                            DisclosureGroup(state.t("ui.setup.details")) {
                                if !operation.changes.isEmpty {
                                    Text(operation.permission + " · " + String(operation.estimatedBytes))
                                }
                                ForEach(operation.changes.keys.filter { $0 != "proton_package" }.sorted(), id: \.self) { key in
                                    Text((plan.snapshot.values[key] ?? "") + " → " + (operation.changes[key] ?? "")).textSelection(.enabled)
                                }
                                if let block = operation.blocked {
                                    Text(state.t(block == "STEAM_TOOL_DISCOVERY_REQUIRED" ? "ui.setup.toolDiscovery" : block.hasPrefix("ARTIFACT_") ? "ui.setup.artifactUnavailable" : "ui.setup.blocked"))
                                }
                                if operation.changes["proton_package"] != nil { Text(state.t("ui.setup.protonInstall")) }
                                if operation.advisory { Text(state.t("ui.setup.ipv6Advisory")) }
                                if !operation.changes.isEmpty { Text(state.t("ui.setup.rollback")) }
                                if plan.snapshot.steamRunning && ["launch", "tool"].contains(operation.component) && operation.blocked != nil {
                                    Text(state.t("ui.setup.steamManual"))
                                    if operation.component == "launch", let value = operation.changes["launch"] {
                                        Text(value).font(.caption.monospaced()).textSelection(.enabled)
                                    }
                                }
                            }
                        }.padding(.vertical, 4)
                    }
                    DisclosureGroup(state.t("ui.setup.evidence")) {
                        ForEach(plan.snapshot.facts.keys.sorted(), id: \.self) { key in
                            Text(key + " = " + (plan.snapshot.facts[key] ?? "UNKNOWN")).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                TacticalPanel(number: "5", title: state.t("ui.setup.deploy"), symbol: "wrench.and.screwdriver") {
                    Text(state.t("ui.setup.authorization"))
                    if plan.executable.contains(where: { $0.needsRestart }) { Text(state.t("ui.setup.autoReboot")) }
                    ForEach(["steam_api_error", "steam_tool_api_error"].filter { plan.snapshot.facts[$0] != nil }, id: \.self) { key in
                        Text(state.t("ui.setup.apiFailure") + " · " + (plan.snapshot.facts[key] ?? "UNKNOWN")).foregroundStyle(.orange)
                    }
                    Button(state.t("ui.setup.deploy")) { authorize = true }.buttonStyle(.borderedProminent)
                        .disabled(plan.executable.isEmpty || plan.snapshot.gameRunning)
                    if plan.snapshot.gameRunning { Text(state.t("ui.setup.closeSteam")).foregroundStyle(.orange) }
                    if plan.snapshot.steamRunning && plan.snapshot.facts["steam_api"] != "available" {
                        Text(state.t("ui.setup.steamManual"))
                        Button(state.t("ui.setup.detect")) { state.firstRunAction("first_run_detect") }
                    }
                    if plan.executable.isEmpty { Text(state.t("ui.setup.noExecutable")) }
                    Button(state.t("ui.setup.graphics")) { state.selection = .performance }
                }
            }
            TacticalPanel(number: "6", title: state.t("ui.setup.result"), symbol: "checkmark.shield") {
                Text(state.t("ui.setup.state." + state.firstRunState.rawValue))
                if let failure = state.firstRunFailure { Text(failure).font(.caption.monospaced()).foregroundStyle(.orange) }
                if let receipt = state.firstRunReceipt {
                    Text(receipt.id.uuidString).font(.caption.monospaced())
                    Text(state.t("ui.setup.applied") + ": " + receipt.applied.map { state.t("ui.setup.component." + $0) }.joined(separator: ", "))
                    ForEach(receipt.plan.operations.filter { $0.blocked != nil || $0.changes.isEmpty || !receipt.applied.contains($0.id) }) { operation in
                        Text(state.t(operation.blocked != nil || !operation.changes.isEmpty && !receipt.applied.contains(operation.id) ? "ui.setup.blocked" : "ui.setup.skip") + ": " + state.t("ui.setup.component." + operation.component))
                    }
                }
                Text(state.t("ui.setup.acceptance"))
                Button(state.t("ui.setup.launch")) { state.selection = .dashboard }
            }
            TacticalPanel(number: "R", title: state.t("ui.setup.recovery"), symbol: "arrow.uturn.backward") {
                Button(state.t("ui.setup.records")) { state.firstRunAction("first_run_receipts") }
                ForEach(state.firstRunReceipts) { receipt in
                    DisclosureGroup(receipt.id.uuidString) {
                        Text(state.t("ui.setup.state." + receipt.state.rawValue))
                        ForEach(receipt.plan.executable.filter { receipt.applied.contains($0.id) || receipt.pending == $0.id }) { operation in
                            Toggle(state.t("ui.setup.component." + operation.component), isOn: Binding(get: { recoverySelection.contains(operation.id) }, set: {
                                if $0 { recoverySelection.insert(operation.id) } else { recoverySelection.remove(operation.id) }
                            }))
                            ForEach(operation.changes.keys.filter { $0 != "proton_package" }.sorted(), id: \.self) { key in
                                Text((receipt.plan.snapshot.values[key] ?? "") + " ← " + (operation.changes[key] ?? "")).font(.caption).textSelection(.enabled)
                                Text(state.t("ui.setup.current") + ": " + (plan?.snapshot.values[key] ?? state.t("ui.368"))).font(.caption)
                            }
                        }
                        Button(state.t("ui.setup.recovery")) { recoverID = receipt.id }.disabled(recoverySelection.isEmpty)
                    }
                }
            }
            }.disabled(tasks.busy)
        }
        .confirmationDialog(state.t("ui.fex.title"), isPresented: Binding(get: { fexAction != nil }, set: { if !$0 { fexAction = nil } }), titleVisibility: .visible) {
            if let action = fexAction {
                Button(state.t(action == "build" ? "ui.fex.build" : action == "install" ? "ui.fex.install" : "ui.fex.recover")) {
                    state.firstRunAction("first_run_fex_" + action, receipt: action == "recover" ? state.firstRunFEXRestore : state.firstRunFEXTicket)
                    fexAction = nil
                }
            }
            Button(state.t("ui.037"), role: .cancel) { fexAction = nil }
        } message: { Text(state.t("ui.fex.scope")) }
        .confirmationDialog(state.t("ui.setup.authorization"), isPresented: $authorize, titleVisibility: .visible) {
            Button(state.t("ui.setup.deploy")) { state.firstRunAction("first_run_deploy") }
        } message: {
            Text(state.t(plan?.executable.contains(where: { $0.needsRestart }) == true ? "ui.setup.autoReboot" : "ui.setup.rollback"))
        }
        .confirmationDialog(state.t("ui.setup.recovery"), isPresented: Binding(get: { recoverID != nil }, set: { if !$0 { recoverID = nil } }), titleVisibility: .visible) {
            Button(state.t("ui.setup.recovery")) {
                if let id = recoverID { state.firstRunAction("first_run_recover", receipt: id, selected: recoverySelection) }
                recoverID = nil; recoverySelection = []
            }
        } message: { Text(state.t("ui.setup.rollback")) }
    }
}


struct EnvironmentWorkflowProgressView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    var showIdle = false
    private var workflow: EnvironmentWorkflow { state.environmentWorkflow }
    var body: some View {
        if showIdle || workflow.phase != .idle {
            TacticalPanel(number: "", title: state.t("ui.workflow.result"), symbol: "gearshape.2") {
                Text(state.t(workflow.launchesGame && workflow.phase == .completed ? "ui.140" : workflow.phase.titleKey))
                if workflow.phase == .launching { Text(state.launchSession.current.title(state.languageCode)) }
                if workflow.phase == .deploying, let stage = workflow.deploymentStage {
                    Text(state.t("ui.setup.state." + stage)).font(TacticalTypography.caption)
                }
                if workflow.active {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(state.t("ui.workflow.stepProgress"))
                        Text("\(workflow.completedSteps)/\(workflow.totalSteps)")
                    }
                }
                ProgressView(value: workflow.fraction).tint(.yellow)
                    .animation(.easeInOut(duration: 0.2), value: workflow.completedSteps)
                Text(state.t("ui.workflow.stepProgress") + " · " + String(Int(workflow.fraction * 100)) + "%")
                if let failure = workflow.failure {
                    Text(failure.message(state.languageCode)).foregroundStyle(.orange)
                    DisclosureGroup(state.t("ui.setup.details")) {
                        Text(failure.code).font(.caption.monospaced())
                        Text(CoreJSON.encode(.object(failure.details))).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    HStack {
                        Button(state.t("ui.workflow.retry")) { state.startEnvironmentWorkflow(launchGame: workflow.launchesGame) }.disabled(tasks.busy)
                        Button(state.t("ui.setup.launch")) { state.selection = .dashboard }
                    }
                }
                if workflow.launchesGame && state.launchSession.current != .idle {
                    DisclosureGroup(state.t("ui.094")) { LaunchProgressView(state: state, tasks: tasks) }
                }
                if workflow.active { Button(state.t("ui.038")) { tasks.cancel() } }
            }
            .confirmationDialog(state.t("ui.setup.autoReboot"), isPresented: Binding(
                get: { state.environmentWorkflow.needsRestartApproval && !tasks.busy },
                set: { if !$0 { state.environmentWorkflow.needsRestartApproval = false } })) {
                    Button(state.t("ui.setup.deploy")) {
                        state.environmentWorkflow.needsRestartApproval = false
                        state.startEnvironmentWorkflow(launchGame: workflow.launchesGame, restartApproved: true)
                    }
                    Button(state.t("ui.037"), role: .cancel) { state.environmentWorkflow.needsRestartApproval = false }
                }
        }
    }
}
