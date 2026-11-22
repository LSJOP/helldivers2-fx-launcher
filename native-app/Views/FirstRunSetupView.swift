import SwiftUI
import AppKit

struct FirstRunSetupView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @ObservedObject var credentials: SessionCredentialManager
    @Environment(\.colorScheme) private var scheme
    @State private var authorize = false
    @State private var fexAction: String?
    @State private var recoverID: UUID?
    @State private var recoverySelection = Set<String>()
    @State private var diagnosticCopied = false
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
        if operation.component == "fex", let plan, plan.setupObservationVerified(operation) { return "ui.net.pass" }
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
    private var verifiedCompletion: DeploymentPlan? {
        guard let plan else { return nil }
        let workflow = state.environmentWorkflow
        let required = plan.operations.filter { !$0.advisory }
        guard workflow.canShowSetupCompletion(busy: tasks.busy, deploymentCompleted: state.firstRunState == .Completed,
                                              hasCurrentBinding: state.fxSelection.selected != nil && state.fxSelection.selectedPath == state.runtimeRoot && !plan.snapshot.boot.isEmpty && state.credentials.guestBoot == plan.snapshot.boot,
                                              hasRequiredObservations: !required.isEmpty,
                                              inspectionReady: plan.firstUnverifiedSetupOperation == nil) else { return nil }
        return plan
    }
    private var setupStatusKey: String {
        if state.environmentWorkflow.active || state.environmentWorkflow.phase == .cancelled { return state.environmentWorkflow.phase.titleKey }
        return state.firstRunState == .NotChecked ? "ui.workflow.idle" : "ui.setup.state." + state.firstRunState.rawValue
    }
    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            TacticalFlowMark()
            Text(state.t("ui.art.welcomeTitle"))
                .font(.system(size: 29, weight: .heavy)).fixedSize(horizontal: false, vertical: true)
            Text(state.t("ui.art.welcomeDetail")).font(.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "checkmark.shield").font(.title2).foregroundStyle(TacticalColors(scheme: scheme).accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(state.t("ui.workflow.environment")).font(.headline)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top) { Text(verbatim: "FX"); Text(state.t(state.fxSelection.selected != nil ? "ui.219" : "ui.210")) }
                        HStack(alignment: .top) { Text(verbatim: "SteamOS"); Text(state.t(state.credentials.guestBoot != nil ? "ui.credentials.status.connected" : "ui.credentials.status.idle")) }
                    }.font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Text(state.t(setupStatusKey)).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(.vertical, 4)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.t("ui.workflow.configure")).font(.headline).padding(.bottom, 8)
                TacticalFlowStep(number: "01", title: state.t("ui.setup.fx"), symbol: "shippingbox")
                TacticalFlowStep(number: "02", title: state.t("ui.setup.detect"), symbol: "magnifyingglass")
                TacticalFlowStep(number: "03", title: state.t("ui.setup.deploy"), symbol: "wrench.and.screwdriver")
                TacticalFlowStep(number: "04", title: state.t("ui.workflow.result"), symbol: "checkmark.shield")
            }
            if state.environmentWorkflow.phase == .idle || state.environmentWorkflow.launchesGame {
                TacticalButton(title: state.t("ui.workflow.begin"), symbol: "play.fill", primary: true, disabledReason: tasks.busy ? state.t("ui.014") : nil, fillsWidth: true) {
                    state.startEnvironmentWorkflow(launchGame: false)
                }
            }
            EnvironmentWorkflowProgressView(state: state, tasks: tasks)
            TacticalFlowFooter()
        }
    }
    private func completionContent(_ plan: DeploymentPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            TacticalFlowMark()
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 48)).foregroundStyle(TacticalColors(scheme: scheme).accent).accessibilityHidden(true)
                Text(state.t("ui.art.completedTitle")).font(.system(size: 27, weight: .heavy))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(state.t("ui.setup.acceptance")).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(state.t("ui.workflow.environment")).font(.headline).padding(.bottom, 9)
                ForEach(Array(plan.operations.enumerated()), id: \.element.id) { index, operation in
                    HStack(spacing: 10) {
                        Text(String(format: "%02d", index + 1)).font(TacticalTypography.log).foregroundStyle(TacticalColors(scheme: scheme).accent).accessibilityHidden(true)
                        Text(state.t("ui.setup.component." + operation.component)).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Text(state.t(statusKey(operation))).font(.caption.weight(.semibold)).multilineTextAlignment(.trailing)
                    }.padding(.vertical, 7)
                    TacticalDivider()
                }
            }
            TacticalButton(title: state.t("ui.176"), symbol: "play.fill", primary: true, disabledReason: tasks.busy ? state.t("ui.014") : nil, fillsWidth: true) {
                state.selection = .dashboard
                state.perform(.game)
            }
            TacticalButton(title: state.t("ui.workflow.retry"), symbol: "arrow.clockwise", primary: false, disabledReason: tasks.busy ? state.t("ui.014") : nil) {
                state.startEnvironmentWorkflow(launchGame: false)
            }
            TacticalFlowFooter()
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TacticalPageHeader(title: state.t("ui.setup.title"))
            if let completed = verifiedCompletion {
                TacticalFlowArtwork(asset: "MOTR7SuperEarth") { completionContent(completed) }
            } else {
                TacticalFlowArtwork(asset: "MOTR7Democracy") { welcomeContent }
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
            DisclosureGroup(state.t("ui.workflow.advanced")) {
            TacticalPanel(number: "1", title: state.t("ui.setup.fx"), symbol: "shippingbox") {
                Button(state.t("ui.setup.choose")) { state.selection = .dashboard }
                Text(state.fxVersion + " · " + (state.fxSelection.selectedPath ?? state.t("ui.368"))).textSelection(.enabled)
                Text(plan?.snapshot.facts["os_version"] ?? state.t("ui.368"))
            }
            TacticalPanel(number: "FX", title: state.t("ui.fex.title"), symbol: "shippingbox") {
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
                            if operation.component == "fex", let code = operation.blocked {
                                Text(code == "FEX_KNOWN_LAUNCH_INCOMPATIBILITY" ? ErrorState(code).message(state.languageCode) : state.t("ui.setup.artifactUnavailable")).font(.caption)
                            }
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
                if state.firstRunState == .Failed || state.environmentWorkflow.failure != nil {
                    Button(state.t(diagnosticCopied ? "ui.setup.diagnosticCopied" : "ui.setup.copyDiagnostic")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.firstRunDiagnosticReport(), forType: .string)
                        diagnosticCopied = true
                    }
                }
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
    @Environment(\.colorScheme) private var scheme
    var showIdle = false
    var showStepsInline = false
    var returnToDashboard: (() -> Void)? = nil
    private var workflow: EnvironmentWorkflow { state.environmentWorkflow }
    @State private var showFEXDetails = false
    @State private var diagnosticCopied = false
    private var stepRows: some View {
        ForEach(Array([EnvironmentWorkflowPhase.startingFX, .connecting, .detecting, .deploying, .verifying, .launching].prefix(workflow.totalSteps).enumerated()), id: \.offset) { index, phase in
            let stepKeys = ["ui.setup.fx", "ui.setup.connect", "ui.setup.detect", "ui.setup.deploy", "ui.workflow.result", "ui.176"]
            let done = index < workflow.completedSteps
            let current = workflow.active && phase == workflow.phase
            HStack(spacing: 10) {
                Text(String(format: "%02d", index + 1)).font(TacticalTypography.log).foregroundStyle(.secondary).accessibilityHidden(true)
                Label(state.t(stepKeys[index]), systemImage: done ? "checkmark.circle.fill" : current ? "arrow.right.circle.fill" : "circle.dashed")
                    .foregroundStyle(done ? TacticalColors(scheme: scheme).success : current ? TacticalColors(scheme: scheme).accent : Color.secondary)
                    .font(TacticalTypography.caption.weight(current ? .bold : .regular))
                Spacer(minLength: 0)
            }.padding(.vertical, 5)
        }
    }
    private var stepDetails: some View {
        Group {
            if workflow.active && workflow.phase == .deploying {
                Text(state.t("ui.fx.installing"))
            } else if workflow.failure != nil,
                      state.environmentWorkflow.evidence["fx_runtime_repair_attempted"]?.boolean == true {
                Text(state.t("ui.fx.repairFailed"))
            } else if workflow.failure == nil, !workflow.active,
                      state.environmentWorkflow.evidence["fx_runtime_repair_attempted"]?.boolean == true {
                Text(state.t("ui.fx.repaired"))
            }
            if let status = state.firstRunPlan?.snapshot.facts["fex_status"] {
                Text(state.t(status == "unverified" ? "ui.fex.integrated" : status == "normal" ? "ui.fex.normal" : status == "compatible" ? "ui.fex.compatible" : status == "confirmation" ? "ui.fex.unverified" : "ui.fex.repair"))
            }
            Text(verbatim: "ID: " + workflow.taskID.uuidString).font(.caption.monospaced()).textSelection(.enabled)
        }
    }
    private var workflowContent: some View {
        VStack(alignment: .leading, spacing: 12) {
                HStack {
                    if !showStepsInline || workflow.phase == .launching {
                        Text(workflow.phase == .launching ? state.launchSession.current.title(state.languageCode) :
                             state.t(workflow.launchesGame && workflow.phase == .failed ? "ui.179" : workflow.phase.titleKey))
                    }
                    Spacer()
                    if workflow.showsProgress { Text(workflow.fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit() }
                }
                if workflow.active {
                    TimelineView(.periodic(from: workflow.startedAt, by: 1)) { context in
                        Text(state.t("ui.logs.elapsed") + " \(max(0, Int(context.date.timeIntervalSince(workflow.startedAt))))s")
                            .font(TacticalTypography.caption).monospacedDigit()
                    }
                }
                if workflow.active {
                    ProgressView(value: workflow.fraction).tint(TacticalColors(scheme: scheme).accent)
                }
                if let failure = workflow.failure {
                    Text(["ARTIFACT_UNAVAILABLE", "ARTIFACT_UNAPPROVED"].contains(failure.code) && failure.details["component"]?.text == "fex"
                         ? "FX · " + state.t("ui.setup.artifactUnavailable")
                         : failure.message(state.languageCode))
                        .foregroundStyle(.orange)
                    DisclosureGroup(state.t("ui.setup.details")) {
                        Text(failure.code).font(.caption.monospaced())
                        Text(CoreJSON.encode(.object(failure.details))).font(.caption.monospaced()).textSelection(.enabled)
                    }
                    HStack {
                        Button(state.t("ui.workflow.retry")) { state.startEnvironmentWorkflow(launchGame: workflow.launchesGame) }.disabled(tasks.busy)
                        Button(state.t(diagnosticCopied ? "ui.setup.diagnosticCopied" : "ui.setup.copyDiagnostic")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(state.firstRunDiagnosticReport(), forType: .string)
                            diagnosticCopied = true
                        }
                        Button(state.t("ui.setup.launch")) {
                            if let returnToDashboard { returnToDashboard() } else { state.selection = .dashboard }
                        }
                    }
                }
                if showStepsInline {
                    stepRows
                    DisclosureGroup(state.t("ui.setup.details")) { stepDetails }
                } else {
                    DisclosureGroup(state.t("ui.workflow.stepProgress")) {
                        stepDetails
                        stepRows
                    }
                }
                if workflow.launchesGame && state.launchSession.current != .idle {
                    DisclosureGroup(state.t("ui.094")) { LaunchProgressView(state: state, tasks: tasks) }
                }
                if workflow.active {
                    Button(state.t("ui.038")) { tasks.cancel() }
                } else if workflow.phase != .idle && workflow.failure == nil {
                    Button(state.t(workflow.launchesGame ? "ui.176" : "ui.workflow.retry")) {
                        state.startEnvironmentWorkflow(launchGame: workflow.launchesGame)
                    }.disabled(tasks.busy)
                }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    var body: some View {
        if showIdle || workflow.phase != .idle {
            Group {
                if showStepsInline {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(spacing: 12) {
                            Image(systemName: "scope").font(.system(size: 32)).foregroundStyle(TacticalColors(scheme: scheme).accent).accessibilityHidden(true)
                            Text(state.t(workflow.phase.titleKey)).font(.system(size: 25, weight: .heavy))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        TacticalDivider()
                        workflowContent
                    }
                    .padding(18)
                    .background(.primary.opacity(0.035))
                    .overlay(alignment: .leading) { Rectangle().fill(TacticalColors(scheme: scheme).accent).frame(width: 3) }
                } else {
                    TacticalPanel(number: "", title: state.t(workflow.launchesGame ? "ui.176" : "ui.workflow.result"), symbol: workflow.launchesGame ? "play.rectangle" : "gearshape.2") {
                        workflowContent
                    }
                }
            }
            .sheet(isPresented: Binding(get: { state.pendingFEXApproval != nil && !tasks.busy }, set: { if !$0 { state.cancelFEXApproval() } })) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(state.t("ui.fex.confirmTitle")).font(.headline)
                    Text(state.t("ui.fex.confirmMessage"))
                    if showFEXDetails {
                        Text(state.firstRunPlan?.snapshot.facts["fex_tree"] ?? "").font(.caption.monospaced()).textSelection(.enabled)
                        Text(state.t("ui.fex.unverified"))
                    }
                    HStack {
                        Button(state.t("ui.fex.continue")) { state.approveFEXBuild() }.buttonStyle(.borderedProminent).tint(.yellow)
                        Button(state.t("ui.setup.details")) { showFEXDetails.toggle() }
                        Button(state.t("ui.037"), role: .cancel) { state.cancelFEXApproval() }
                    }
                }.padding(24).frame(width: 540)
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
