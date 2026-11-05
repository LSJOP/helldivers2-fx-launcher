import SwiftUI

struct FirstRunSetupView: View {
    @ObservedObject var state: AppState
    @ObservedObject var tasks: TaskManager
    @ObservedObject var credentials: SessionCredentialManager
    @State private var authorize = false
    @State private var recoverID: UUID?
    @State private var recoverySelection = Set<String>()
    private var plan: DeploymentPlan? { state.firstRunPlan }
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
            Text(state.t("ui.setup.scope"))
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
                Text(state.t("ui.setup.credentials")).font(.caption)
                HStack {
                    Button(state.t("ui.setup.detect")) { state.firstRunAction("first_run_detect") }
                    Button(state.t("ui.setup.sudo")) { state.operationSelection = NativeOperation(method: "test_guest_sudo") }
                }
                if let snapshot = plan?.snapshot {
                    Text(state.t("ui.setup.identity") + " · " + String(snapshot.boot.prefix(8)) + " · " + snapshot.architecture)
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
                                    if operation.component == "launch", operation.blocked == nil, let value = operation.changes["launch"] {
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
        }
        .disabled(tasks.busy)
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
