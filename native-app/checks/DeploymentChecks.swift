import Foundation
import Darwin

/// Filesystem backend exercises the production engine, durable receipts and compare-and-swap
/// against real isolated files. It never connects to SSH, a VM or user preferences.
final class FileDeploymentBackend: DeploymentBackend {
    let url: URL
    var state: DeploymentSnapshot
    var writes = 0
    var failAfterWrite = false, disconnect = false, recoveryFails = false
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
        try check(profile.artifacts.isEmpty, "no unreviewed public artifacts")
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
        try check(p.operations.first { $0.id == "proton" }?.blocked == "ARTIFACT_UNAPPROVED", "missing Proton is blocked")
        try check(p.executable.map(\.id) == ["launch"], "only approved available configuration is executable")
        try fails("CONFIRMATION_REQUIRED", "exact operation consent required") { _ = try s.execute(p, approved: [], context: CoreContext(timeout: 10)) }
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
