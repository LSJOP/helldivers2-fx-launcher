import Foundation
import Darwin

/// Filesystem backend exercises the production engine, durable receipts and compare-and-swap
/// against real isolated files. It never connects to SSH, a VM or user preferences.
final class FileDeploymentBackend: DeploymentBackend {
    let url: URL
    var state: DeploymentSnapshot
    var writes = 0
    var failAfterWrite = false, disconnect = false, recoveryFails = false
    var changeLaunchAfterPackage = false
    init(_ url: URL, state: DeploymentSnapshot) throws {
        self.url = url; self.state = state
        try CoreFS.atomicWrite(try JSONEncoder().encode(state.values), to: url)
    }
    func snapshot() throws -> DeploymentSnapshot {
        if disconnect { throw CoreError("SSH_CONNECTION_REFUSED") }
        let bytes = try Data(contentsOf: url)
        var live = state
        live.values = try JSONDecoder().decode([String: String].self, from: bytes)
        live.revision = CoreHash.sha256(bytes)
        return live
    }
    func replace(_ changes: [String: String], expected: DeploymentSnapshot) throws {
        let live = try snapshot()
        guard live.revision == expected.revision, EnvironmentDeploymentService.identity(live, expected) else { throw CoreError("CONFIG_CHANGED") }
        if recoveryFails && writes > 0 { throw CoreError("RECOVERY_FAILED") }
        var values = live.values; values.merge(changes) { _, new in new }
        if changeLaunchAfterPackage && changes["proton_package"] == ProtonJERelease.digest { values["launch"] = "%command% --external-edit" }
        try CoreFS.atomicWrite(try JSONEncoder().encode(values), to: url)
        writes += 1
        if failAfterWrite { failAfterWrite = false; throw CoreError("SSH_CONNECTION_TIMEOUT") }
    }
}
@main struct DeploymentChecks {
    static func main() throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/hd2-deployment-checks-" + UUID().uuidString)
        try CoreFS.ensurePrivateDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        var count = 0
        func check(_ condition: @autoclosure () throws -> Bool, _ name: String) throws {
            guard try condition() else { throw CoreError("ASSERTION_FAILED", ["test": .string(name)]) }
            count += 1; print("PASS " + name)
        }
        func fails(_ code: String? = nil, _ name: String, _ action: () throws -> Void) throws {
            do { try action() } catch let error as CoreError {
                try check(code == nil || code == error.code, name); return
            } catch { if code == nil { try check(true, name); return }; throw error }
            throw CoreError("EXPECTED_FAILURE", ["test": .string(name)])
        }
        let profile = try EnvironmentProfile.load(URL(fileURLWithPath: "Resources/environment-profile-v1.json"))
        let baselineData = try Data(contentsOf: URL(fileURLWithPath: "Resources/successful-environment-baseline-v1.json"))
        let baseline = try JSONDecoder().decode(SuccessfulEnvironmentBaseline.self, from: baselineData)
        try baseline.validate()
        try check(baseline.fxVersion.value == "1.9.4" && baseline.protonArchiveBytes == 348_245_820, "successful baseline is machine-readable and evidence-bound")
        try check(baseline.ipv6Policy == "diagnostic_only_non_blocking", "baseline cannot turn IPv6 into a mutation")
        try check(profile.artifacts.count == 1 && profile.artifacts[0].component == "proton", "only the reviewed Proton release is approved")
        try check(profile.requirements["ipv4"] == .OPTIONAL, "IPv4-only stays optional")
        try check(profile.launchOptions["https_proxy"] == nil, "no hardcoded proxy")
        func fixture() throws -> (FileDeploymentBackend, EnvironmentDeploymentService, DeploymentPlan) {
            let dir = root.appendingPathComponent(UUID().uuidString); try CoreFS.ensurePrivateDirectory(dir)
            let snapshot = DeploymentSnapshot(target: "fixture-target", boot: UUID().uuidString, revision: "",
                fxVersion: "1.9.8", osVersion: "0.4.5", architecture: "aarch64", steamRunning: false, gameRunning: false,
                freeBytes: 128 * 1_048_576, facts: ["steam": "present", "game": "present", "ipv4": "available", "gvproxy": "available"], values: ["launch": "%command%", "tool": "other-tool"])
            let backend = try FileDeploymentBackend(dir.appendingPathComponent("config.json"), state: snapshot)
            let service = EnvironmentDeploymentService(backend: backend, receipts: .init(directory: dir.appendingPathComponent("receipts")))
            return (backend, service, DeploymentPlanBuilder.build(try backend.snapshot(), profile: profile))
        }
        func execute(_ service: EnvironmentDeploymentService, _ plan: DeploymentPlan) throws -> DeploymentReceipt {
            try service.execute(plan, approved: Set(plan.executable.map(\.id)), context: CoreContext(timeout: 10))
        }
        let (b, s, p) = try fixture()
        try check(p.operations.first { $0.id == "fex" }?.blocked == "ARTIFACT_UNAPPROVED", "missing FEX is blocked")
        try check(p.operations.first { $0.id == "proton" }?.blocked == "ARTIFACT_IMPORT_REQUIRED", "missing Proton without exact-target detection is blocked")
        try check(p.executable.map(\.id) == ["launch"], "only approved available configuration is executable")
        var missingProton = p.snapshot
        missingProton.facts["proton_manifest"] = "UNKNOWN"
        missingProton.values["component.proton"] = "missing"
        missingProton.values["proton_package"] = "missing"
        missingProton.values["tool"] = "other-tool"
        let protonPlan = DeploymentPlanBuilder.build(missingProton, profile: profile)
        try check(protonPlan.operations.first { $0.id == "proton" }?.changes["proton_package"] == ProtonJERelease.digest,
                  "missing Proton gets an exact pinned install operation")
        try check(Set(protonPlan.executable.map(\.id)) == ["proton", "launch", "tool"], "one confirmation covers available Proton and configuration steps")
        let remoteProton = SSHEnvironmentBackend.protonInstallScript(boot: p.snapshot.boot)
        try remoteProton.write(to: URL(fileURLWithPath: "evidence/proton-install-script.sh"), atomically: true, encoding: .utf8)
        for marker in ["--proto '=https'", "--proto-redir '=https'", "--tlsv1.2", "--max-filesize 348245820",
                       "sha256sum \"$archive\"", "find \"$stage\" -type l", "realpath -m", "! -type d ! -type f ! -type l",
                       "[ ! -e \"$p\" ]", "mv \"$stage\" \"$p\""] {
            try check(remoteProton.contains(marker), "Proton installer safety marker: " + marker)
        }
        try check(!remoteProton.contains("sudo") && !remoteProton.contains("rm -rf /"), "Proton install is user-scoped and cleanup-bounded")
        let remoteRollback = SSHEnvironmentBackend.protonRollbackScript(boot: p.snapshot.boot, suffix: UUID().uuidString)
        try remoteRollback.write(to: URL(fileURLWithPath: "evidence/proton-rollback-script.sh"), atomically: true, encoding: .utf8)
        try check(remoteRollback.contains("hd2-recovered-") && remoteRollback.contains("mv \"$p\" \"$retained\"") && !remoteRollback.contains("rm "),
                  "Proton rollback retains the installed tree instead of deleting it")
        try fails("CONFIRMATION_REQUIRED", "exact operation consent required") { _ = try s.execute(p, approved: [], context: CoreContext(timeout: 10)) }
        var runningSteam = p.snapshot
        runningSteam.steamRunning = true
        let runningPlan = DeploymentPlanBuilder.build(runningSteam, profile: profile)
        try check(runningPlan.executable.isEmpty, "running Steam defers managed file writes per operation")
        try check(runningPlan.operations.first { $0.id == "launch" }?.changes == p.operations.first { $0.id == "launch" }?.changes, "deferred launch target remains available for manual Steam properties")
        try check(runningPlan.operations.first { $0.id == "tool" }?.blocked == "ARTIFACT_UNAPPROVED", "manual guidance never approves an unverified compatibility tool")
        try EnvironmentDeploymentService.idle(runningSteam, requiresStoppedSteam: false)
        try check(true, "SteamOS Steam is not a global idle prerequisite")
        try fails("STEAM_RUNNING", "Steam-owned writes retain process guard") { try EnvironmentDeploymentService.idle(runningSteam) }
        runningSteam.gameRunning = true
        try fails("GAME_RUNNING", "game guard remains even without Steam stop requirement") { try EnvironmentDeploymentService.idle(runningSteam, requiresStoppedSteam: false) }
        do {
            let (onlineBackend, onlineService, basePlan) = try fixture()
            onlineBackend.state.freeBytes = 8 * 1_073_741_824
            onlineBackend.state.steamRunning = true
            onlineBackend.state.facts["steam_api"] = "available"
            onlineBackend.state.facts["steam_tool_api"] = "available"
            onlineBackend.state.facts["restart_completed"] = "true"
            onlineBackend.state.facts["proton_manifest"] = "verified"
            onlineBackend.state.facts["proton_discovered"] = "true"
            onlineBackend.state.values["proton_package"] = "missing"
            try CoreFS.atomicWrite(try JSONEncoder().encode(onlineBackend.state.values), to: onlineBackend.url)
            let online = DeploymentPlanBuilder.build(try onlineBackend.snapshot(), profile: profile)
            try check(online.executable.map(\.id) == ["proton", "launch", "tool"], "missing pinned Proton and live launch settings are executable with Steam running")
            let result = try execute(onlineService, online)
            try check(result.state == .Completed && onlineBackend.writes == 3, "package and live launch settings share durable ordered receipts")
            let restored = try onlineService.recover(result.id, selected: ["proton", "launch", "tool"])
            try check(restored.state == .Ready && (try onlineBackend.snapshot()).values["proton_package"] == "missing", "package receipt recovery restores absent state")
            var discovered = basePlan.snapshot
            discovered.steamRunning = true; discovered.facts["steam_api"] = "available"
            discovered.facts["proton_manifest"] = "verified"
            let pendingTool = DeploymentPlanBuilder.build(discovered, profile: profile)
            try check(pendingTool.operations.first { $0.id == "tool" }?.blocked == "STEAM_TOOL_API_UNAVAILABLE", "tool selection requires its own live API read")
            discovered.facts["steam_tool_api"] = "available"
            discovered.facts["restart_completed"] = "true"
            try check(DeploymentPlanBuilder.build(discovered, profile: profile).executable.map(\.id).contains("tool"), "verified discovered tool can be selected online")
            discovered.values["proton_package"] = "unknown"; discovered.facts["proton_manifest"] = "UNKNOWN"
            try check(!DeploymentPlanBuilder.build(discovered, profile: profile).executable.map(\.id).contains("proton"), "unknown existing Proton is never overwritten")
        }
        do {
            let (deferredBackend, deferredService, _) = try fixture()
            deferredBackend.state.freeBytes = 8 * 1_073_741_824
            deferredBackend.state.steamRunning = true
            deferredBackend.state.facts["steam_api"] = "available"
            deferredBackend.state.facts["steam_tool_api"] = "available"
            deferredBackend.state.facts["proton_manifest"] = "verified"
            deferredBackend.state.facts["proton_discovered"] = "false"
            deferredBackend.state.values["proton_package"] = "missing"
            try CoreFS.atomicWrite(try JSONEncoder().encode(deferredBackend.state.values), to: deferredBackend.url)
            let staged = DeploymentPlanBuilder.build(try deferredBackend.snapshot(), profile: profile)
            let result = try execute(deferredService, staged)
            try check(result.state == .NeedsConfiguration && result.applied == ["proton", "launch"] && deferredBackend.writes == 2,
                      "undiscovered tool stays pending without undoing verified installation and launch settings")
        }
        do {
            let (driftBackend, driftService, _) = try fixture()
            driftBackend.state.freeBytes = 8 * 1_073_741_824; driftBackend.state.steamRunning = true
            driftBackend.state.facts["steam_api"] = "available"
            driftBackend.state.values["proton_package"] = "missing"
            driftBackend.changeLaunchAfterPackage = true
            try CoreFS.atomicWrite(try JSONEncoder().encode(driftBackend.state.values), to: driftBackend.url)
            let staged = DeploymentPlanBuilder.build(try driftBackend.snapshot(), profile: profile)
            let result = try execute(driftService, staged)
            try check(result.state == .Failed && result.failure == "CONFIG_CHANGED" && (try driftBackend.snapshot()).values["launch"] == "%command% --external-edit",
                      "Steam settings changed during package download are preserved without overwrite")
        }
        do {
            var old = p.snapshot; old.facts["machine_id"] = String(repeating: "a", count: 32)
            old.facts["fx_path"] = "/fixture/FX.app"
            old.facts["fx_executable_sha256"] = String(repeating: "c", count: 64)
            old.facts["ssh_connection"] = String(repeating: "d", count: 64)
            var restarted = old; restarted.boot = UUID().uuidString; restarted.target = "fixture-new-process-binding"
            try SetupVMReboot.validateTransition(old: old, new: restarted)
            try check(true, "expected reboot accepts verified same installation and new boot/process binding")
            var foreignExecutable = restarted; foreignExecutable.facts["fx_executable_sha256"] = String(repeating: "e", count: 64)
            try fails("TARGET_CHANGED", "replaced FX executable cannot inherit reboot authorization") { try SetupVMReboot.validateTransition(old: old, new: foreignExecutable) }
            try fails("TARGET_CHANGED", "unchanged boot cannot claim reboot completed") { try SetupVMReboot.validateTransition(old: old, new: old) }
            restarted.facts["machine_id"] = String(repeating: "b", count: 32)
            try fails("TARGET_CHANGED", "different Guest cannot reuse reboot credentials") { try SetupVMReboot.validateTransition(old: old, new: restarted) }
            let cancelled = CoreContext(timeout: 3); cancelled.cancel(); var calls = 0
            try fails("CANCELLED", "cancelled reconnect never probes or authenticates") { try SetupVMReboot.wait(context: cancelled, seconds: 1) { calls += 1; return true } }
            try check(calls == 0, "cancellation stops reconnect before IO")
            let script = try GuestPrivilegedExecutor.script(.reboot(boot: old.boot, machine: old.facts["machine_id"]!, ticket: UUID()))
            try check(script.contains("systemd-run --on-active=5s --collect") && script.contains("/usr/bin/systemctl reboot") && !script.contains("pkill") && !script.contains("--force"), "VM reboot is one delayed graceful systemd request")
            try check(script.contains("reaper helldivers2.exe") && script.contains("/etc/machine-id") && script.contains("/proc/sys/kernel/random/boot_id"), "reboot checks game and exact Guest immediately before scheduling")
            var verified = old; verified.facts["proton"] = "verified"; verified.facts["proton_manifest"] = "verified"; verified.values["tool"] = profile.protonVersion
            try check(DeploymentPlanBuilder.build(verified, profile: profile).operations.first { $0.id == "proton" }?.detectionPassed == true,
                      "fully verified Proton is reported passed rather than merely found")
        }
        do {
            let dir = root.appendingPathComponent("reboot-script"); try CoreFS.ensurePrivateDirectory(dir)
            let bin = dir.appendingPathComponent("bin"); try CoreFS.ensurePrivateDirectory(bin)
            let boot = UUID().uuidString, machine = String(repeating: "a", count: 32)
            let bootFile = dir.appendingPathComponent("boot"), machineFile = dir.appendingPathComponent("machine")
            try Data(boot.utf8).write(to: bootFile); try Data(machine.utf8).write(to: machineFile)
            let commandFile = dir.appendingPathComponent("scheduled"), gameFile = dir.appendingPathComponent("game")
            try CoreFS.atomicWrite(Data(("#!/bin/sh\nprintf '%s' \"$*\" > " + SSHEnvironmentBackend.quote(commandFile.path) + "\n").utf8), to: bin.appendingPathComponent("systemd-run"), mode: 0o755)
            try CoreFS.atomicWrite(Data(("#!/bin/sh\n[ -f " + SSHEnvironmentBackend.quote(gameFile.path) + " ] && exit 0\nexit 1\n").utf8), to: bin.appendingPathComponent("pgrep"), mode: 0o755)
            let fakeSystemctl = bin.appendingPathComponent("systemctl"); try CoreFS.atomicWrite(Data("#!/bin/sh\nexit 99\n".utf8), to: fakeSystemctl, mode: 0o755)
            let script = try GuestPrivilegedExecutor.script(.reboot(boot: boot, machine: machine, ticket: UUID()))
                .replacingOccurrences(of: "/proc/sys/kernel/random/boot_id", with: bootFile.path)
                .replacingOccurrences(of: "/etc/machine-id", with: machineFile.path)
                .replacingOccurrences(of: "/usr/bin/systemctl", with: fakeSystemctl.path)
            let env = ["PATH": bin.path + ":/usr/bin:/bin", "HOME": dir.path]
            let scheduled = try CoreProcess.run("/bin/sh", ["-c", script], timeout: 5, environment: env)
            try check(scheduled.status == 0 && scheduled.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "HD2FX_REBOOT_SCHEDULED" && FileManager.default.fileExists(atPath: commandFile.path), "production reboot script schedules only the fixture systemd command")
            try FileManager.default.removeItem(at: commandFile); try Data().write(to: gameFile)
            let blocked = try CoreProcess.run("/bin/sh", ["-c", script], timeout: 5, environment: env)
            try check(blocked.status == 75 && !FileManager.default.fileExists(atPath: commandFile.path), "production reboot script blocks a running game before scheduling")
            try FileManager.default.removeItem(at: gameFile); try Data(UUID().uuidString.utf8).write(to: bootFile)
            let changed = try CoreProcess.run("/bin/sh", ["-c", script], timeout: 5, environment: env)
            try check(changed.status == 73 && !FileManager.default.fileExists(atPath: commandFile.path), "production reboot script rejects changed boot without scheduling")
        }
        do {
            var original = p.snapshot
            original.steamRunning = true; original.facts["steam_api"] = "available"; original.facts["steam_tool_api"] = "available"
            original.facts["proton_manifest"] = "verified"
            let approved = DeploymentPlanBuilder.build(original, profile: profile)
            var after = original; after.boot = UUID().uuidString; after.facts["restart_completed"] = "true"
            let safe = SetupVMReboot.approvedFollowup(original: approved, fresh: DeploymentPlanBuilder.build(after, profile: profile))
            try check(safe.executable.contains { $0.id == "tool" }, "post-reboot unchanged tool can complete the exact approved target")
            after.values["tool"] = "external-user-tool"
            let changed = SetupVMReboot.approvedFollowup(original: approved, fresh: DeploymentPlanBuilder.build(after, profile: profile))
            try check(!changed.executable.contains { $0.id == "tool" }, "post-reboot user tool edit cannot be overwritten by old approval")
        }
        try fails("TARGET_CHANGED", "unowned or unauthenticated SSH cannot become the shared post-reboot session") {
            var settings = SSHTransport.make([:]).settings
            settings.socketPath = "/tmp/hd2-fixture-no-session-" + UUID().uuidString + ".sock"
            try SSHTransport.adoptReconnected(SSHTransport(settings: settings), configuration: [:], context: CoreContext(timeout: 5))
        }
        let stdinStart = CoreClock.monotonic
        let blockedInput = try CoreProcess.run("/bin/sleep", ["2"], input: String(repeating: "x", count: 2 * 1_048_576), timeout: 0.1)
        try check(blockedInput.timedOut && CoreClock.monotonic - stdinStart < 1.5, "large stdin obeys deadline when peer never reads")
        try check(try SteamSetupClient.endpoint("ws://127.0.0.1:8080/devtools/page/fixture", port: 41234).port == 41234, "CDP websocket remains on setup-owned loopback tunnel")
        for address in ["ws://example.com:8080/devtools/page/x", "wss://127.0.0.1:8080/devtools/page/x", "ws://127.0.0.1:9999/devtools/page/x", "ws://user@127.0.0.1:8080/devtools/page/x"] {
            try fails("STEAM_API_UNAVAILABLE", "untrusted CDP endpoint rejected") { _ = try SteamSetupClient.endpoint(address, port: 41234) }
        }
        for (name, expression) in [("read", SteamSetupClient.launchExpression()), ("write", SteamSetupClient.launchExpression(previous: "%command%", desired: "FEX_DISKCACHE=0 %command%")), ("drift", SteamSetupClient.launchExpression(previous: "stale", desired: "FEX_DISKCACHE=0 %command%")), ("tool", SteamSetupClient.toolExpression(desired: ProtonJERelease.version, previous: "proton_11-arm64"))] {
            try expression.write(to: root.appendingPathComponent(name + ".js"), atomically: true, encoding: .utf8)
        }
        let receipt = try execute(s, p)
        try check(receipt.state == .Completed && b.writes == 1, "real config written and verified")
        try check(try s.receipts.read(receipt.id).applied == ["launch"], "durable receipt readback")
        let repeated = DeploymentPlanBuilder.build(try b.snapshot(), profile: profile)
        try check(repeated.executable.isEmpty, "repeat detection does not duplicate options")
        let recovered = try s.recover(receipt.id, selected: ["launch"])
        try check(recovered.state == .Ready && (try b.snapshot()).values["launch"] == "%command%", "explicit receipt recovery restores originals")
        try fails("INVALID_ARGUMENT", "completed restore cannot run twice") { _ = try s.recover(receipt.id, selected: ["launch"]) }
        for scenario in ["steam", "game", "space", "identity", "revision", "disconnect", "cancel"] {
            let (b, s, p) = try fixture()
            switch scenario {
            case "steam": b.state.steamRunning = true
            case "game": b.state.gameRunning = true
            case "space": b.state.freeBytes = 0
            case "identity": b.state.boot = UUID().uuidString
            case "revision": try CoreFS.atomicWrite(Data("{\"launch\":\"external\",\"tool\":\"other-tool\"}".utf8), to: b.url)
            case "disconnect": b.disconnect = true
            default: break
            }
            if scenario == "cancel" {
                let context = CoreContext(timeout: 10); context.cancel()
                let result = try s.execute(p, approved: ["launch"], context: context)
                try check(result.state == .Failed && b.writes == 0, "cancellation stops before mutation")
            } else { try fails(nil, scenario + " guard prevents write") { _ = try execute(s, p) }; try check(b.writes == 0, scenario + " unchanged") }
        }
        do {
            let (b, s, p) = try fixture(); b.failAfterWrite = true
            let result = try execute(s, p)
            try check(result.state == .Failed && result.failure == "SSH_CONNECTION_TIMEOUT", "interrupted write reports failure")
            try check((try b.snapshot()).values["launch"] == "%command%", "pending write safely recovered")
        }
        do {
            let (b, s, p) = try fixture(); b.failAfterWrite = true; b.recoveryFails = true
            try fails("RECOVERY_REQUIRED", "failed recovery retains blocked receipt") { _ = try execute(s, p) }
            try check(try s.receipts.list().first?.state == .RecoveryRequired, "recovery required persisted")
            b.recoveryFails = false
            let next = DeploymentPlanBuilder.build(try b.snapshot(), profile: profile)
            // Explicitly recover the pending step after a new process could reopen the store.
            let persisted = try s.receipts.list()[0]
            _ = next
            _ = try s.recover(persisted.id, selected: ["launch"])
            try check((try b.snapshot()).values["launch"] == "%command%", "restart recovery uses durable receipt")
        }
        do {
            let (b, s, p) = try fixture(); let r = try execute(s, p)
            try CoreFS.atomicWrite(Data("{\"launch\":\"external-update\",\"tool\":\"other-tool\"}".utf8), to: b.url)
            try fails("EXTERNAL_DRIFT", "external update prevents restore") { _ = try s.recover(r.id, selected: ["launch"]) }
            try check((try b.snapshot()).values["launch"] == "external-update", "external state preserved")
        }
        do {
            let (b, s, p) = try fixture(); let receipt = try execute(s, p)
            let file = s.receipts.directory.appendingPathComponent(receipt.id.uuidString + ".json")
            var envelope = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
            envelope["sha256"] = String(repeating: "0", count: 64)
            try CoreFS.atomicWrite(try JSONSerialization.data(withJSONObject: envelope), to: file)
            let before = try b.snapshot()
            try fails("RECEIPT_INVALID", "corrupt receipt blocks recovery") { _ = try s.recover(receipt.id, selected: ["launch"]) }
            try check(try b.snapshot() == before, "corrupt receipt never changes target")
        }
        var mismatch = p.snapshot
        for (fx, os) in [("1.9.9", "0.4.5"), ("2.0", "0.5.0"), ("future-build", "rolling")] {
            mismatch.fxVersion = fx; mismatch.osVersion = os
            let updated = DeploymentPlanBuilder.build(mismatch, profile: profile)
            try check(updated.operations == p.operations, "version updates preserve capability and artifact decisions: " + fx + "/" + os)
        }
        mismatch = p.snapshot; mismatch.architecture = "x86_64"
        try check(DeploymentPlanBuilder.build(mismatch, profile: profile).operations.filter { !$0.detectionPassed }.allSatisfy { $0.blocked == "UNSUPPORTED" }, "architecture mismatch blocks configuration without overriding passed detection")
        let architecturePlan = DeploymentPlanBuilder.build(mismatch, profile: profile)
        for id in ["steam", "game", "ipv4", "gvproxy"] {
            try check(architecturePlan.operations.first { $0.id == id }?.detectionPassed == true && architecturePlan.operations.first { $0.id == id }?.blocked == nil, "passed detection survives unrelated deployment block: " + id)
        }
        mismatch = p.snapshot; mismatch.facts["fex"] = LaunchService.verifiedFEX
        try check(DeploymentPlanBuilder.build(mismatch, profile: profile).operations.first { $0.id == "fex" }?.blocked != nil, "single known hash cannot establish complete FEX")
        var observed = p.snapshot
        observed.facts["fex"] = "present"; observed.facts["proton"] = "present"
        observed.facts["ipv6"] = "UNKNOWN"
        let observedPlan = DeploymentPlanBuilder.build(observed, profile: profile)
        for id in ["fex", "proton"] {
            let op = observedPlan.operations.first { $0.id == id }!
            try check(op.observation == .found && !op.warning && op.blocked == (id == "proton" ? "ARTIFACT_IMPORT_REQUIRED" : "ARTIFACT_UNAPPROVED"), "installed component is neutral while deployment stays protected: " + id)
        }
        let ipv6 = observedPlan.operations.first { $0.id == "ipv6" }!
        try check(ipv6.warning && ipv6.advisory && ipv6.blocked == nil, "unknown IPv6 warns without blocking")
        try check(observedPlan.executable.map(\.id) == p.executable.map(\.id), "IPv6 does not change executable operations")
        let readyWithIPv6 = DeploymentPlan(id: UUID(), profileID: p.profileID, profileVersion: p.profileVersion, snapshot: observed,
            operations: observedPlan.operations.filter { ["steam", "game", "ipv4", "gvproxy", "ipv6"].contains($0.id) })
        try check(readyWithIPv6.detectionState == .Ready, "IPv6 warning does not block readiness")
        for id in ["kosmickrisp", "network"] {
            let op = observedPlan.operations.first { $0.id == id }!
            try check(op.observation == .unverified && !op.warning && op.blocked == nil, "unknown evidence stays unverified: " + id)
        }
        let discoveryHome = root.appendingPathComponent("discovery")
        let steam = discoveryHome.appendingPathComponent(".local/share/Steam")
        let tool = steam.appendingPathComponent("compatibilitytools.d/Proton-JE-future")
        try CoreFS.ensurePrivateDirectory(tool)
        try CoreFS.atomicWrite(Data(), to: tool.appendingPathComponent("proton"))
        try CoreFS.atomicWrite(Data(), to: tool.appendingPathComponent("compatibilitytool.vdf"))
        let discovery = String(SSHEnvironmentBackend.probe.components(separatedBy: "# Bounded file discovery only:")[1].components(separatedBy: "for pair in")[0])
        let discoveryScript = "set -eu\nS=" + SSHEnvironmentBackend.quote(steam.path) + "\n# Bounded file discovery only:" + discovery
        let discovered = try CoreProcess.run("/bin/sh", ["-s"], input: discoveryScript.replacingOccurrences(of: "$HOME", with: discoveryHome.path), timeout: 5)
        try check(discovered.status == 0 && discovered.stdout.contains("proton=present"), "discover newer Proton-JE directory without executing it")
        let nodeCandidates = ["/opt/homebrew/bin/node", "/usr/local/bin/node", NSHomeDirectory() + "/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node"]
        if let node = nodeCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            let portFile = root.appendingPathComponent("cdp-port.txt")
            let server = Process(); server.executableURL = URL(fileURLWithPath: node)
            server.arguments = ["checks/steam_cdp_fixture.js", portFile.path]
            server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
            try server.run(); defer { server.terminate(); server.waitUntilExit() }
            try SetupVMReboot.wait(context: CoreContext(timeout: 5), seconds: 4) { FileManager.default.fileExists(atPath: portFile.path) }
            guard let port = Int(try String(contentsOf: portFile)) else { throw CoreError("ASSERTION_FAILED") }
            let socketRead = try SteamSetupClient.evaluate(SteamSetupClient.launchExpression(), port: port, context: CoreContext(timeout: 10))
            try check(socketRead["launch"]?.text == "%command%", "native URLSession reads actual CDP HTTP and websocket protocol")
            let socketTool = try SteamSetupClient.evaluate(SteamSetupClient.toolExpression(), port: port, context: CoreContext(timeout: 10))
            try check(socketTool["tool"]?.text == "proton_11-arm64", "tool read is independent of missing legacy tools-list API")
            let socketWrite = try SteamSetupClient.evaluate(SteamSetupClient.launchExpression(previous: "%command%", desired: "FEX_DISKCACHE=0 %command%"), port: port, context: CoreContext(timeout: 10))
            try check(socketWrite["saved"]?.boolean == true, "native CDP confirms launch options through callback")
            try fails("CONFIG_CHANGED", "native CDP preserves structured CAS failure") {
                _ = try SteamSetupClient.evaluate(SteamSetupClient.launchExpression(previous: "stale", desired: "%command%"), port: port, context: CoreContext(timeout: 10))
            }
            let fixtureJS = #"""
            const fs=require('fs');
            (async()=>{
              let callback=null,writes=0;
              let data={strLaunchOptions:'%command%',strCompatToolName:'proton_11-arm64',strCompatToolDisplayName:'Proton ARM64'};
              global.appDetailsStore={RegisterForAppData(_id,cb){callback=cb;cb({...data});return {unregister(){callback=null;}};}};
              global.SteamUIStore={RunningApps:[]};
              global.SteamClient={Apps:{SetAppLaunchOptions(id,v){if(id!==553850)throw Error('appid');writes++;data.strLaunchOptions=v;callback({...data});},SpecifyCompatTool(id,v){if(id!==553850)throw Error('appid');writes++;data.strCompatToolName=v;data.strCompatToolDisplayName=v;callback({...data});}}};
              const read=JSON.parse(await eval(fs.readFileSync(process.argv[1]+'/read.js','utf8')));
              if(read.launch!=='%command%')throw Error('read');
              try {await eval(fs.readFileSync(process.argv[1]+'/drift.js','utf8'));throw Error('drift accepted');}catch(e){if(e.message!=='changed')throw e;}
              const saved=JSON.parse(await eval(fs.readFileSync(process.argv[1]+'/write.js','utf8')));
              if(!saved.saved||writes!==1||callback!==null)throw Error('write');
              const tool=JSON.parse(await eval(fs.readFileSync(process.argv[1]+'/tool.js','utf8')));
              if(!tool.saved||data.strCompatToolName!=='proton-je-11.0-20261014-3')throw Error('tool');
              SteamUIStore.RunningApps=[{}];
              try {await eval(fs.readFileSync(process.argv[1]+'/write.js','utf8'));throw Error('game accepted');}catch(e){if(e.message!=='game_running')throw e;}
              SteamUIStore.RunningApps=undefined;
              try {await eval(fs.readFileSync(process.argv[1]+'/tool.js','utf8'));throw Error('unknown running accepted');}catch(e){if(e.message!=='running_state_unavailable')throw e;}
              if(writes!==2||callback!==null||SteamClient.Apps.GetAvailableCompatTools!==undefined)throw Error('unexpected state');
            })().catch(e=>{console.error(e);process.exitCode=1;});
            """#
            let jsResult = try CoreProcess.run(node, ["-e", fixtureJS, root.path], timeout: 10)
            try check(jsResult.status == 0, "production expressions use observed Steam API shape without absent tools/running methods")
        } else { throw CoreError("PROCESS_UNAVAILABLE", ["binary": .string("fixture-node")]) }
        let original = "CUSTOM=foo %command% --user-flag"
        let merged = try LaunchOptionsAdapter.merge(original, managed: profile.launchOptions)
        try check(merged.contains("CUSTOM=foo") && merged.hasSuffix("--user-flag"), "custom arguments preserved")
        try check(try LaunchOptionsAdapter.merge(merged, managed: profile.launchOptions) == merged, "launch merge idempotent")
        for conflict in ["FEX_DISKCACHE=1 %command%", "FEX_DISKCACHE=0 FEX_DISKCACHE=0 %command%", "FEX_DISKCACHE='0' %command%", "%command% FEX_DISKCACHE=1", "%command%\nrm -rf /"] {
            try fails("LAUNCH_OPTIONS_CONFLICT", "launch conflict stops mutation") { _ = try LaunchOptionsAdapter.merge(conflict, managed: profile.launchOptions) }
        }
        let vdf = "\"UserLocalConfigStore\" { \"Software\" { \"Valve\" { \"Steam\" { \"apps\" { \"553850\" { \"Other\" \"keep\" } \"123\" { \"LaunchOptions\" \"untouched\" } } } } } }"
        let edited = try SteamVDF(vdf).setting(SteamVDF.launchPath, value: merged)
        try check(try SteamVDF(edited).value(SteamVDF.launchPath) == merged, "VDF insert and structural readback")
        try check(edited.contains("\"Other\" \"keep\"") && edited.contains("\"LaunchOptions\" \"untouched\""), "unrelated games and values preserved")
        try fails("VDF_CONFLICT", "duplicate VDF paths rejected") { _ = try SteamVDF("\"apps\" {} \"apps\" {}") }
        try fails("VDF_CONFLICT", "malformed VDF rejected") { _ = try SteamVDF("\"x\" {") }
        try fails("PROFILE_NOT_APPLICABLE", "network requires profile and consent") { _ = try NetworkConfigurationAdapter.ipv4Plan(current: ["lo": "0"], profileAllows: false, consent: true) }
        try check(try NetworkConfigurationAdapter.ipv4Plan(current: ["lo": "0"], profileAllows: true, consent: true) == ["lo": "1"], "conditional network proposal is scoped")
        // Build a real small tar to test whole-package validation, corruption and traversal.
        let payloadDir = root.appendingPathComponent("payload"); try CoreFS.ensurePrivateDirectory(payloadDir)
        try CoreFS.atomicWrite(Data("component".utf8), to: payloadDir.appendingPathComponent("proton"), mode: 0o755)
        let tar = root.appendingPathComponent("component.tar")
        let tarResult = try CoreProcess.run("/usr/bin/tar", ["--format=ustar", "-cf", tar.path, "-C", payloadDir.path, "proton"], timeout: 10)
        try check(tarResult.status == 0, "real isolated tar created")
        let artifact = ApprovedArtifact(component: "proton", version: profile.protonVersion, source: "https://example.invalid/reviewed", license: "fixture-only", buildRecord: "isolated-test", archiveSHA256: try CoreHash.sha256File(tar), files: ["proton": CoreHash.sha256(Data("component".utf8))])
        let payload = try ApprovedPayload(archive: tar, approved: artifact)
        try check(payload.files["proton"] == Data("component".utf8), "full approved package import")
        // Execute the actual generated POSIX installer/recovery against an isolated HOME.
        // Only /proc boot reads and external Linux utilities are mapped to fixture stubs.
        let home = root.appendingPathComponent("guest-home").resolvingSymlinksInPath()
        let bin = root.appendingPathComponent("bin").resolvingSymlinksInPath(); try CoreFS.ensurePrivateDirectory(bin); try CoreFS.ensurePrivateDirectory(home)
        let bootFile = root.appendingPathComponent("boot").resolvingSymlinksInPath()
        let boot = p.snapshot.boot; try CoreFS.atomicWrite(Data(boot.utf8), to: bootFile)
        try CoreFS.atomicWrite(Data("#!/bin/sh\n[ -f \"$HOME/running\" ] && exit 0\nexit 1\n".utf8), to: bin.appendingPathComponent("pgrep"), mode: 0o755)
        try CoreFS.atomicWrite(Data("#!/bin/sh\nexec /usr/bin/shasum -a 256 \"$@\"\n".utf8), to: bin.appendingPathComponent("sha256sum"), mode: 0o755)
        try CoreFS.atomicWrite(Data("#!/bin/sh\ncase \"$1\" in *.hd2-stage-*) if [ -f \"$HOME/fail-move\" ]; then exit 1; fi;; esac\nexec /bin/mv \"$@\"\n".utf8), to: bin.appendingPathComponent("mv"), mode: 0o755)
        func run(_ script: String) throws -> CoreProcessResult {
            try CoreProcess.run("/bin/sh", ["-x", "-s"], input: script.replacingOccurrences(of: "/proc/sys/kernel/random/boot_id", with: bootFile.path), timeout: 10,
                environment: ["HOME": home.path, "PATH": bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL": "C"])
        }
        let relative = "compatibilitytools.d/" + profile.protonVersion
        let installed = home.appendingPathComponent(".local/share/Steam/" + relative)
        let installID = UUID()
        let installScript = try ComponentDeploymentAdapter.installScript(payload: payload, knownCurrent: nil, live: p.snapshot, relative: relative, suffix: installID.uuidString)
        let installedResult = try run(installScript)
        if installedResult.status != 0 { print("INSTALL FIXTURE status=\(installedResult.status) stderr=\(installedResult.stderr)"); try installScript.write(to: root.appendingPathComponent("debug-install.sh"), atomically: true, encoding: .utf8) }
        try check(installedResult.status == 0, "production package script installs staged full tree")
        try check(try Data(contentsOf: installed.appendingPathComponent("proton")) == Data("component".utf8), "installed package readback")
        try check(try run(installScript).status != 0, "unknown existing component never overwritten")
        let keep = try ComponentDeploymentAdapter.installScript(payload: payload, knownCurrent: artifact.files, live: p.snapshot, relative: relative, suffix: UUID().uuidString)
        try check(try run(keep).status == 0, "matching complete component skipped")
        let oldData = Data("original-component".utf8)
        try CoreFS.atomicWrite(oldData, to: installed.appendingPathComponent("proton"))
        let oldManifest = ["proton": CoreHash.sha256(oldData)]
        let replaceID = UUID()
        let replaceScript = try ComponentDeploymentAdapter.installScript(payload: payload, knownCurrent: oldManifest, live: p.snapshot, relative: relative, suffix: replaceID.uuidString)
        try check(try run(replaceScript).status == 0, "known component version transaction replaces after verification")
        let packageReceipt = ComponentInstallReceipt(id: replaceID, target: p.snapshot.target, boot: boot, component: "proton", version: profile.protonVersion, manifest: artifact.files, originalManifest: oldManifest, backup: relative + ".hd2-backup-" + replaceID.uuidString, state: .Completed)
        let restoreScript = try ComponentDeploymentAdapter.recoveryScript(receipt: packageReceipt, live: p.snapshot, relative: relative)
        try check(try run(restoreScript).status == 0, "production package recovery restores retained original tree")
        try check(try Data(contentsOf: installed.appendingPathComponent("proton")) == oldData, "package restore full readback")
        let interruptedID = UUID()
        let interruptedScript = try ComponentDeploymentAdapter.installScript(payload: payload, knownCurrent: oldManifest, live: p.snapshot, relative: relative, suffix: interruptedID.uuidString)
        try CoreFS.atomicWrite(Data(), to: home.appendingPathComponent("fail-move"))
        try check(try run(interruptedScript).status != 0, "injected package replacement interruption is detected")
        try FileManager.default.removeItem(at: home.appendingPathComponent("fail-move"))
        let interruptedReceipt = ComponentInstallReceipt(id: interruptedID, target: p.snapshot.target, boot: boot, component: "proton", version: profile.protonVersion, manifest: artifact.files, originalManifest: oldManifest, backup: relative + ".hd2-backup-" + interruptedID.uuidString, state: .RecoveryRequired)
        try check(try run(ComponentDeploymentAdapter.recoveryScript(receipt: interruptedReceipt, live: p.snapshot, relative: relative)).status == 0, "interrupted directory swap safely recovered")
        try CoreFS.atomicWrite(Data(), to: home.appendingPathComponent("running"))
        try check(try run(keep).status != 0, "package script rejects running Steam/game")
        try FileManager.default.removeItem(at: home.appendingPathComponent("running"))
        try CoreFS.atomicWrite(Data(UUID().uuidString.utf8), to: bootFile)
        try check(try run(keep).status != 0, "package script rejects changed VM boot")
        try artifact.verify(directory: payloadDir, archive: tar)
        try check(true, "full manifest including exact inventory validated")
        try CoreFS.atomicWrite(Data("mixed".utf8), to: payloadDir.appendingPathComponent("unexpected"))
        try fails("ARTIFACT_HASH", "mixed Proton tree rejected") { try artifact.verify(directory: payloadDir, archive: tar) }
        try CoreFS.atomicWrite(Data("damaged".utf8), to: tar)
        try fails("ARTIFACT_HASH", "corrupt package rejected") { _ = try ApprovedPayload(archive: tar, approved: artifact) }
        try check(!ApprovedArtifact.safe("../escape") && !ApprovedArtifact.safe("/root/file"), "archive traversal rejected")
        print("\(count) deployment checks passed; SSH/VM/game NOT_TESTED")
    }
}
