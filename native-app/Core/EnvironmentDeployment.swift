import Foundation
import Darwin

// Versioned policy is bundled, never inferred from a single historical fingerprint.
enum DeploymentState: String, Codable, CaseIterable {
    case Rebooting, Reconnecting, CheckingSteam, NotChecked, Checking, Ready, NeedsConfiguration, AwaitingAuthorization, Deploying, Verifying
    case Completed, Failed, RecoveryRequired, Unsupported
}
enum Requirement: String, Codable { case REQUIRED, CONDITIONAL, OPTIONAL, UNKNOWN }
enum EvidenceLevel: String, Codable { case observed, reproduced, multiplayer, upstream, inferred, unknown }
struct BaselineEvidence: Codable {
    let value: String, level: EvidenceLevel, source: String
}
struct SuccessfulEnvironmentBaseline: Codable {
    let id: String, schemaVersion: Int, fxVersion: BaselineEvidence, steamOSVersion: BaselineEvidence
    let architecture: BaselineEvidence, fexVersion: BaselineEvidence, fexExecutableSHA256: BaselineEvidence
    let protonVersion: BaselineEvidence, protonArchiveSHA256: BaselineEvidence, protonArchiveBytes: Int64
    let protonNTDLLSHA256: BaselineEvidence, graphicsPath: BaselineEvidence, vulkanDriver: BaselineEvidence
    let managedLaunchOptions: [String: BaselineEvidence], observedLaunchOptions: [String: BaselineEvidence]
    let ipv6Policy: String, acceptance: [String: BaselineEvidence]
    func validate() throws {
        guard schemaVersion == 1, fxVersion.level != .inferred, steamOSVersion.level != .inferred,
              architecture.value == "aarch64", ApprovedArtifact.hash(fexExecutableSHA256.value),
              ApprovedArtifact.hash(protonArchiveSHA256.value), ApprovedArtifact.hash(protonNTDLLSHA256.value),
              protonArchiveBytes > 0, ipv6Policy == "diagnostic_only_non_blocking" else { throw CoreError("BASELINE_INVALID") }
    }
    static func bundled() throws -> SuccessfulEnvironmentBaseline {
        guard let url = Bundle.main.url(forResource: "successful-environment-baseline-v1", withExtension: "json") else { throw CoreError("BASELINE_INVALID") }
        let data = try Data(contentsOf: url)
        guard data.count < 1_048_576 else { throw CoreError("BASELINE_INVALID") }
        let result = try JSONDecoder().decode(Self.self, from: data); try result.validate(); return result
    }
}
struct EnvironmentProfile: Codable {
    let id: String, version: Int, fx: [String], steamOS: [String], architecture: String, appID: String
    let fexVersion: String, protonVersion: String, vulkan: String
    let launchOptions: [String: String]
    let requirements: [String: Requirement]
    let artifacts: [ApprovedArtifact]
    let networkCandidates: [String], sources: [String], licenses: [String], testedScope: [String]
    static func load(_ url: URL) throws -> EnvironmentProfile {
        let data = try Data(contentsOf: url)
        guard data.count < 1_048_576 else { throw CoreError("PROFILE_INVALID") }
        let p = try JSONDecoder().decode(Self.self, from: data)
        guard p.version == 1, p.appID == "553850", p.architecture == "aarch64", !p.fx.isEmpty,
              p.requirements["fex"] != nil, p.requirements["proton"] != nil else { throw CoreError("PROFILE_INVALID") }
        for artifact in p.artifacts { try artifact.validate() }
        return p
    }
    static func bundled() throws -> EnvironmentProfile {
        guard let url = Bundle.main.url(forResource: "environment-profile-v1", withExtension: "json") else { throw CoreError("PROFILE_INVALID") }
        return try load(url)
    }
}
struct ApprovedArtifact: Codable {
    let component: String, version: String, source: String, license: String, buildRecord: String
    let archiveSHA256: String, files: [String: String]
    func validate() throws {
        guard ["fex", "proton"].contains(component), source.hasPrefix("https://"), !license.isEmpty,
              !buildRecord.isEmpty, Self.hash(archiveSHA256), !files.isEmpty,
              files.allSatisfy({ Self.safe($0.key) && Self.hash($0.value) }) else { throw CoreError("ARTIFACT_UNAPPROVED") }
    }
    static func hash(_ text: String) -> Bool { text.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil }
    static func safe(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0 == ".." || $0 == "." || $0.isEmpty }) && !path.contains("\n") && !path.contains("\\")
    }
    /// Validate the entire imported payload, including extra/mixed files. Symlinks need an
    /// explicitly reviewed package format; this importer rejects them rather than follows them.
    func verify(directory: URL, archive: URL) throws {
        try validate()
        guard try CoreHash.sha256File(archive, limit: Int.max) == archiveSHA256 else { throw CoreError("ARTIFACT_HASH") }
        guard let iterator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey, .isRegularFileKey]) else { throw CoreError("ARTIFACT_HASH") }
        var actual: [String: String] = [:]
        for case let url as URL in iterator {
            let v = try url.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey])
            guard v.isSymbolicLink != true else { throw CoreError("UNSAFE_PATH") }
            if v.isRegularFile == true {
                let root = directory.resolvingSymlinksInPath().path
                let canonical = url.resolvingSymlinksInPath().path
                guard canonical.hasPrefix(root + "/") else { throw CoreError("UNSAFE_PATH") }
                let relative = String(canonical.dropFirst(root.count + 1))
                guard files[relative] != nil else { throw CoreError("ARTIFACT_HASH") }
                actual[relative] = try CoreHash.sha256File(url, limit: Int.max)
            }
        }
        guard actual == files else { throw CoreError("ARTIFACT_HASH") }
    }
}
struct DeploymentSnapshot: Codable, Equatable {
    var target: String, boot: String, revision: String, fxVersion: String, osVersion: String, architecture: String
    var steamRunning: Bool, gameRunning: Bool, freeBytes: Int64
    var facts: [String: String]
    var values: [String: String]
}
enum DeploymentObservation { case advisory, passed, found, unverified, blocked, unchanged, change }
struct DeploymentOperation: Codable, Identifiable, Equatable {
    let id: String, component: String, currentVersion: String, targetVersion: String
    let changes: [String: String], permission: String, estimatedBytes: Int64, needsRestart: Bool
    let backupLocation: String, rollback: String, verification: String
    let requirement: Requirement, blocked: String?
    var requiresStoppedSteam: Bool { !["ipv6", "launch", "tool"].contains(component) && !(component == "proton" && changes["proton_package"] != nil) }
    var observation: DeploymentObservation {
        if component == "ipv6", !detectionPassed { return .advisory }
        if detectionPassed { return .passed }
        if ["fex", "proton"].contains(component), currentVersion == "present" { return .found }
        if currentVersion == "UNKNOWN", changes.isEmpty { return .unverified }
        if blocked != nil { return .blocked }
        return changes.isEmpty ? .unchanged : .change
    }
    var warning: Bool {
        component == "ipv6" && !detectionPassed || (blocked != nil && !detectionPassed && currentVersion != "present" && currentVersion != "UNKNOWN")
    }
    var advisory: Bool { component == "ipv6" }
    // A successful bounded observation is independent of permission to deploy changes.
    var detectionPassed: Bool {
        if ["fex", "proton"].contains(component) && currentVersion == "verified" { return true }
        return ["steam", "game", "vulkan", "kosmickrisp", "network", "gvproxy", "ipv4", "ipv6", "launch"].contains(component)
            && ["present", "configured", "available"].contains(currentVersion)
    }
}
struct DeploymentPlan: Codable {
    let id: UUID, profileID: String, profileVersion: Int, snapshot: DeploymentSnapshot
    let operations: [DeploymentOperation]
    var executable: [DeploymentOperation] { operations.filter { !$0.advisory && $0.blocked == nil && !$0.changes.isEmpty && !(snapshot.steamRunning && $0.requiresStoppedSteam) } }
    var detectionState: DeploymentState {
        let required = operations.filter { !$0.advisory }
        if !required.isEmpty && required.allSatisfy({ $0.blocked == "UNSUPPORTED" }) { return .Unsupported }
        return required.allSatisfy { $0.blocked == nil && $0.changes.isEmpty && $0.detectionPassed } ? .Ready : .NeedsConfiguration
    }
}
enum DeploymentPlanBuilder {
    static func build(_ snapshot: DeploymentSnapshot, profile: EnvironmentProfile) -> DeploymentPlan {
        var ops: [DeploymentOperation] = []
        func add(_ component: String, target: String, changes: [String: String] = [:], block: String? = nil, restart: Bool = false, bytes: Int64 = 0, observed: String? = nil) {
            ops.append(.init(id: component, component: component, currentVersion: observed ?? snapshot.facts[component] ?? "UNKNOWN",
                             targetVersion: target, changes: changes, permission: component == "network" ? "Guest sudo" : "user",
                             estimatedBytes: bytes, needsRestart: restart, backupLocation: "receipt/" + component,
                             rollback: "compare_current_then_restore_receipt", verification: "read_back_and_compare",
                             requirement: profile.requirements[component] ?? .UNKNOWN, blocked: block))
        }
        // The historical baseline is evidence, not a version allowlist. These scoped
        // transactions validate architecture, exact package contents and live Steam APIs.
        let baselineApplicable = profile.architecture == snapshot.architecture
        for (component, version) in [("fex", profile.fexVersion), ("proton", profile.protonVersion)] {
            let verified = snapshot.facts[component + "_manifest"] == "verified" || (component == "fex" && snapshot.facts["fex_runtime"] == "ready")
            let artifact = profile.artifacts.first { $0.component == component && $0.version == version }
            if component == "fex", let status = snapshot.facts["fex_status"] {
                add(component, target: version, block: ["normal", "compatible"].contains(status) ? nil : snapshot.facts["fex_reason"] ?? "FEX_RUNTIME_FAILED", observed: status)
            } else if component == "proton", snapshot.values["proton_package"] == "missing", version == ProtonJERelease.version {
                add(component, target: version, changes: ["proton_package": ProtonJERelease.digest], restart: true, bytes: 4 * 1_073_741_824)
            } else {
                add(component, target: version, block: verified ? nil : component == "proton" && snapshot.values["proton_package"] == "unknown" ? "COMPONENT_CONFLICT" : artifact == nil ? "ARTIFACT_UNAPPROVED" : "ARTIFACT_IMPORT_REQUIRED", observed: verified ? "verified" : nil)
            }
        }
        for component in ["steam", "game", "vulkan", "kosmickrisp", "network", "gvproxy", "ipv4", "ipv6"] {
            let fact = snapshot.facts[component] ?? "UNKNOWN"
            add(component, target: component == "vulkan" ? profile.vulkan : "detect", block: component == "ipv6" || fact == "UNKNOWN" || ["present", "configured", "available"].contains(fact) ? nil : "USER_ACTION_REQUIRED")
        }
        do {
            let before = snapshot.values["launch"] ?? ""
            let after = try LaunchOptionsAdapter.merge(before, managed: profile.launchOptions)
            var changes = before == after ? [:] : ["launch": after]
            if !changes.isEmpty, snapshot.values["launch_present"] != nil { changes["launch_present"] = "true" }
            add("launch", target: "profile-v1", changes: changes, block: snapshot.values["launch"] == nil ? "USER_ACTION_REQUIRED" : snapshot.steamRunning && snapshot.facts["steam_api"] != "available" ? "STEAM_API_UNAVAILABLE" : nil, observed: snapshot.values["launch"] != nil && changes.isEmpty ? "configured" : nil)
        } catch { add("launch", target: "profile-v1", block: "LAUNCH_OPTIONS_CONFLICT") }
        if snapshot.values["tool"] != profile.protonVersion {
            var changes = ["tool": profile.protonVersion]
            if snapshot.values["tool_present"] != nil { changes["tool_present"] = "true" }
            let installing = snapshot.values["proton_package"] == "missing" && profile.protonVersion == ProtonJERelease.version
            let verified = snapshot.facts["proton_manifest"] == "verified"
            let toolOnline = snapshot.facts["steam_tool_api"] == "available"
            let block = snapshot.values["tool"] == nil ? "STEAM_TOOL_READ_FAILED" :
                !verified && !installing ? "ARTIFACT_UNAPPROVED" :
                snapshot.steamRunning && !toolOnline ? "STEAM_TOOL_API_UNAVAILABLE" : nil
            add("tool", target: profile.protonVersion, changes: changes, block: block,
                restart: snapshot.steamRunning && snapshot.facts["restart_completed"] != "true")
        }
        if !baselineApplicable {
            ops = ops.map { $0.detectionPassed ? $0 : .init(id: $0.id, component: $0.component, currentVersion: $0.currentVersion, targetVersion: $0.targetVersion,
                                 changes: $0.changes, permission: $0.permission, estimatedBytes: $0.estimatedBytes, needsRestart: $0.needsRestart,
                                 backupLocation: $0.backupLocation, rollback: $0.rollback, verification: $0.verification,
                                 requirement: $0.requirement, blocked: "UNSUPPORTED") }
        }
        return .init(id: UUID(), profileID: profile.id, profileVersion: profile.version, snapshot: snapshot, operations: ops)
    }
}

/// Only leading simple assignments are managed. Shell operators/quoted variables remain
/// untouched; duplicate/conflicting managed assignments stop the transaction.
enum LaunchOptionsAdapter {
    static func merge(_ original: String, managed: [String: String]) throws -> String {
        guard original.utf8.count < 16384, !original.contains("\n"), !original.contains("\r"),
              !CoreRedaction.containsSecret(original) else { throw CoreError("LAUNCH_OPTIONS_CONFLICT") }
        var rest = original[...], prefix: [String] = [], seen = Set<String>()
        while !rest.isEmpty {
            rest = rest.drop(while: { $0 == " " || $0 == "\t" })
            guard let eq = rest.firstIndex(of: "=") else { break }
            let name = String(rest[..<eq])
            guard name.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { break }
            let end = rest.firstIndex(where: { $0 == " " || $0 == "\t" }) ?? rest.endIndex
            let token = String(rest[..<end])
            guard token.range(of: "^[A-Za-z_][A-Za-z0-9_]*=[A-Za-z0-9_./,:+-]*$", options: .regularExpression) != nil else {
                if managed[name] != nil { throw CoreError("LAUNCH_OPTIONS_CONFLICT") }; break
            }
            if let desired = managed[name] {
                guard seen.insert(name).inserted, token == name + "=" + desired else { throw CoreError("LAUNCH_OPTIONS_CONFLICT") }
            }
            prefix.append(token); rest = rest[end...]
        }
        let suffix = String(rest)
        for name in managed.keys where suffix.range(of: "\\b" + NSRegularExpression.escapedPattern(for: name) + "=", options: .regularExpression) != nil { throw CoreError("LAUNCH_OPTIONS_CONFLICT") }
        let additions = managed.keys.sorted().filter { !seen.contains($0) }.map { $0 + "=" + managed[$0]! }
        if additions.isEmpty { return original }
        let command = suffix.isEmpty ? "%command%" : suffix
        guard command.components(separatedBy: "%command%").count == 2 else { throw CoreError("LAUNCH_OPTIONS_CONFLICT") }
        return (prefix + additions + [command]).joined(separator: " ")
    }
}

protocol DeploymentBackend: AnyObject {
    func snapshot() throws -> DeploymentSnapshot
    /// Compare-and-swap must recheck target identity, processes, complete revision and original
    /// values on the destination immediately before its atomic replacement.
    func replace(_ changes: [String: String], expected: DeploymentSnapshot) throws
}
struct DeploymentReceipt: Codable, Identifiable {
    var id: UUID, plan: DeploymentPlan, state: DeploymentState, applied: [String], pending: String?, failure: String?
}
struct DeploymentReceiptEnvelope: Codable { let version: Int; let sha256: String; let receipt: DeploymentReceipt }
final class DeploymentReceiptStore {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func save(_ receipt: DeploymentReceipt) throws {
        try CoreFS.ensurePrivateDirectory(directory)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let digest = CoreHash.sha256(try encoder.encode(receipt))
        let envelope = DeploymentReceiptEnvelope(version: 1, sha256: digest, receipt: receipt)
        let file = directory.appendingPathComponent(receipt.id.uuidString + ".json")
        try CoreFS.atomicWrite(try encoder.encode(envelope), to: file)
        let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }; try handle.synchronize()
        let fd = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw CoreError("WRITE_FAILED") }; defer { close(fd) }
        guard fsync(fd) == 0 else { throw CoreError("WRITE_FAILED") }
    }
    func read(_ id: UUID) throws -> DeploymentReceipt {
        let file = directory.appendingPathComponent(id.uuidString + ".json")
        guard !FileManager.default.isSymbolicLink(atPath: file.path) else { throw CoreError("UNSAFE_PATH") }
        let data = try Data(contentsOf: file)
        guard data.count < 4 * 1_048_576 else { throw CoreError("OUTPUT_LIMIT") }
        let envelope = try JSONDecoder().decode(DeploymentReceiptEnvelope.self, from: data)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard envelope.version == 1, envelope.receipt.id == id,
              CoreHash.sha256(try encoder.encode(envelope.receipt)) == envelope.sha256 else { throw CoreError("RECEIPT_INVALID") }
        return envelope.receipt
    }
    func list() throws -> [DeploymentReceipt] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).compactMap { name in
            guard let id = UUID(uuidString: String(name.dropLast(5))), name.hasSuffix(".json") else { return nil }
            return try read(id)
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}
final class EnvironmentDeploymentService {
    let backend: DeploymentBackend, receipts: DeploymentReceiptStore
    init(backend: DeploymentBackend, receipts: DeploymentReceiptStore) { self.backend = backend; self.receipts = receipts }
    static func identity(_ a: DeploymentSnapshot, _ b: DeploymentSnapshot) -> Bool {
        a.target == b.target && a.boot == b.boot && a.fxVersion == b.fxVersion && a.osVersion == b.osVersion && a.architecture == b.architecture
    }
    static func idle(_ live: DeploymentSnapshot, requiresStoppedSteam: Bool = true) throws {
        guard !live.gameRunning else { throw CoreError("GAME_RUNNING") }
        guard !requiresStoppedSteam || !live.steamRunning else { throw CoreError("STEAM_RUNNING") }
    }
    func execute(_ plan: DeploymentPlan, approved: Set<String>, context: CoreContext, progress: (DeploymentState) -> Void = { _ in }) throws -> DeploymentReceipt {
        guard !plan.executable.isEmpty, approved == Set(plan.executable.map(\.id)) else { throw CoreError("CONFIRMATION_REQUIRED") }
        let lock = try CoreFileLock.acquire(receipts.directory.appendingPathComponent(".deployment.lock")); defer { lock.release() }
        let live = try backend.snapshot()
        guard Self.identity(live, plan.snapshot), live.revision == plan.snapshot.revision, live.values == plan.snapshot.values else { throw CoreError("CONFIG_CHANGED") }
        try Self.idle(live, requiresStoppedSteam: plan.executable.contains { $0.requiresStoppedSteam || (["launch", "tool"].contains($0.component) && plan.snapshot.facts["steam_api"] != "available") })
        guard live.freeBytes >= plan.executable.reduce(0, { $0 + $1.estimatedBytes }) + 1_048_576 else { throw CoreError("INSUFFICIENT_SPACE") }
        for var old in try receipts.list() where old.state == .RecoveryRequired {
            let keys = ["machine_id", "fx_path", "fx_executable_sha256", "ssh_connection"]
            let sameEnvironment = keys.allSatisfy {
                guard let value = old.plan.snapshot.facts[$0], !value.isEmpty else { return false }
                return live.facts[$0] == value
            }
            let affected = old.plan.operations.filter { old.applied.contains($0.id) || old.pending == $0.id }
            // An external manual restore can resolve a receipt without another write.
            // Only exact original values on the same persistent environment qualify.
            if sameEnvironment && !affected.isEmpty && affected.allSatisfy({ operation in
                operation.changes.keys.allSatisfy { live.values[$0] == old.plan.snapshot.values[$0] }
            }) {
                old.applied = []; old.pending = nil; old.state = .Failed
                old.failure = "EXTERNALLY_RESTORED"
                try receipts.save(old)
            }
        }
        guard !(try receipts.list()).contains(where: { [.Deploying, .Verifying, .RecoveryRequired].contains($0.state) }) else { throw CoreError("RECOVERY_REQUIRED") }
        var receipt = DeploymentReceipt(id: plan.id, plan: plan, state: .Deploying, applied: [], pending: nil, failure: nil)
        progress(.Deploying)
        try receipts.save(receipt) // Durable original values precede every write.
        do {
            var expected = live
            var deferred = false
            for operation in plan.executable {
                try context.check()
                let current = try backend.snapshot()
                guard Self.identity(current, expected), current.revision == expected.revision, current.values == expected.values else { throw CoreError("CONFIG_CHANGED") }
                try Self.idle(current, requiresStoppedSteam: operation.requiresStoppedSteam)
                if operation.component == "tool", current.steamRunning, operation.needsRestart {
                    deferred = true; continue // The confirmed workflow restarts the VM before applying tool selection.
                }
                guard operation.changes.keys.allSatisfy({ current.values[$0] == plan.snapshot.values[$0] }) else { throw CoreError("CONFIG_CHANGED") }
                receipt.pending = operation.id; try receipts.save(receipt)
                try backend.replace(operation.changes, expected: current)
                receipt.state = .Verifying; progress(.Verifying); try receipts.save(receipt)
                expected = try backend.snapshot()
                guard Self.identity(expected, live), operation.changes.allSatisfy({ expected.values[$0.key] == $0.value }) else { throw CoreError("VERIFY_FAILED") }
                receipt.applied.append(operation.id); receipt.pending = nil; receipt.state = .Deploying; try receipts.save(receipt)
            }
            receipt.state = deferred ? .NeedsConfiguration : .Completed
            progress(receipt.state); try receipts.save(receipt); return receipt
        } catch {
            receipt.failure = (error as? CoreError)?.code ?? "DEPLOYMENT_FAILED"
            receipt.state = .RecoveryRequired; try receipts.save(receipt)
            if receipt.failure == "STEAM_TOOL_UNCONFIRMED" { throw CoreError("RECOVERY_REQUIRED", ["receipt": .string(receipt.id.uuidString)]) }
            if receipt.applied.isEmpty && receipt.pending == nil { receipt.state = .Failed; try receipts.save(receipt); return receipt }
            // Recovery has its own bounded context/connection. A disconnected SSH never
            // triggers a retry or a guessed success; its durable receipt remains pending.
            do { return try recover(receipt.id, selected: Set(receipt.applied + [receipt.pending].compactMap { $0 }), locked: true) }
            catch { throw CoreError("RECOVERY_REQUIRED", ["receipt": .string(receipt.id.uuidString)]) }
        }
    }
    func recover(_ id: UUID, selected: Set<String>, locked: Bool = false) throws -> DeploymentReceipt {
        let lock = locked ? nil : try CoreFileLock.acquire(receipts.directory.appendingPathComponent(".deployment.lock")); defer { lock?.release() }
        var receipt = try receipts.read(id)
        let ids = Set(receipt.applied + [receipt.pending].compactMap { $0 })
        guard !selected.isEmpty, selected.isSubset(of: ids) else { throw CoreError("INVALID_ARGUMENT") }
        do {
            for operation in receipt.plan.executable.reversed() where selected.contains(operation.id) {
                let current = try backend.snapshot()
                guard Self.identity(current, receipt.plan.snapshot) else { throw CoreError("TARGET_CHANGED") }
                try Self.idle(current, requiresStoppedSteam: operation.requiresStoppedSteam)
                if operation.component == "tool", receipt.pending == operation.id, receipt.failure == "STEAM_TOOL_UNCONFIRMED",
                   current.steamRunning, current.values["tool"] == receipt.plan.snapshot.values["tool"] {
                    throw CoreError("RECOVERY_REQUIRED") // A pending in-memory setter cannot be declared restored from an old disk value.
                }
                var before: [String: String] = [:]
                for (key, after) in operation.changes {
                    let original = receipt.plan.snapshot.values[key] ?? ""
                    guard current.values[key] == after || current.values[key] == original else { throw CoreError("EXTERNAL_DRIFT") }
                    before[key] = original
                }
                if before.contains(where: { current.values[$0.key] != $0.value }) { try backend.replace(before, expected: current) }
                let verified = try backend.snapshot()
                guard Self.identity(verified, current), before.allSatisfy({ verified.values[$0.key] == $0.value }) else { throw CoreError("RECOVERY_FAILED") }
                receipt.applied.removeAll { $0 == operation.id }
                if receipt.pending == operation.id { receipt.pending = nil }
                try receipts.save(receipt)
            }
            receipt.state = receipt.applied.isEmpty && receipt.pending == nil ? (receipt.failure == nil ? .Ready : .Failed) : .RecoveryRequired
            try receipts.save(receipt); return receipt
        } catch {
            receipt.state = .RecoveryRequired; try receipts.save(receipt); throw error
        }
    }
}
