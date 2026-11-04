import Foundation

/// Runtime sysctls only. The complete interface snapshot includes all's cascade.
struct GuestIPv6Snapshot: Equatable {
    let boot: String
    let values: [String: String]
    static let primary = ["all", "default", "eth0", "lo"]
    static func validName(_ key: String) -> Bool {
        key != "." && key != ".." && key.range(of: #"^[A-Za-z0-9_.:-]{1,32}$"#, options: .regularExpression) != nil
    }
    var valid: Bool {
        UUID(uuidString: boot) != nil && values.count <= 128 &&
        Self.primary.allSatisfy { values[$0] != nil } &&
        values.allSatisfy { Self.validName($0.key) && ["0", "1"].contains($0.value) }
    }
    var status: String {
        guard valid else { return "unknown" }
        let selected = Self.primary.compactMap { values[$0] }
        if selected.allSatisfy({ $0 == "0" }) { return "enabled" }
        if selected.allSatisfy({ $0 == "1" }) { return "disabled" }
        return "mixed"
    }
    func desired(enabled: Bool) -> [String: String] {
        var next = values
        for key in Self.primary { next[key] = enabled ? "0" : "1" }
        return next
    }
    static func parse(_ text: String) throws -> GuestIPv6Snapshot {
        let lines = text.split(separator: "\n").map(String.init)
        guard let boot = lines.first, UUID(uuidString: boot) != nil else { throw CoreError("GUEST_INSPECTION_FAILED") }
        var values: [String: String] = [:]
        for line in lines.dropFirst() {
            let parts = line.split(separator: "=", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, validName(parts[0]), values[parts[0]] == nil else { throw CoreError("GUEST_INSPECTION_FAILED") }
            values[parts[0]] = parts[1]
        }
        return GuestIPv6Snapshot(boot: boot, values: values)
    }
}

enum SteamOSNetworkService {
    static let readScript = #"""
cat /proc/sys/kernel/random/boot_id || exit 71
for f in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
  [ -f "$f" ] || continue
  k=${f%/disable_ipv6}; k=${k##*/}
  printf '%s=' "$k"; cat "$f" || exit 71
done
"""#
    struct Bound {
        let transport: SSHTransport
        let session: GuestSession
        let fx: URL
        let context: CoreContext
        var stableTarget: String? = nil
        var receiptIdentity: String { stableTarget ?? session.identitySignature }
        // Internal dependency seams used by isolated transaction tests, never request parameters.
        var readProbe: ((CoreContext) throws -> GuestIPv6Snapshot)? = nil
        var identityProbe: ((CoreContext) throws -> Void)? = nil
        var idleProbe: ((CoreContext) throws -> Void)? = nil
        func verify(_ ctx: CoreContext) throws {
            if let identityProbe { try identityProbe(ctx); return }
            _ = try GuestService.verify(transport, session: session, context: ctx) {
                try LaunchService.hostIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!, transport: transport, context: ctx, requireCDP: false, allowPublisherNetwork: true)
            }
        }
        func read(_ ctx: CoreContext) throws -> GuestIPv6Snapshot {
            try verify(ctx)
            if let readProbe { return try readProbe(ctx) }
            let result = try transport.run(readScript, timeout: 8, context: ctx)
            guard result.status == 0 else { throw CoreError("GUEST_INSPECTION_FAILED") }
            let snapshot = try GuestIPv6Snapshot.parse(result.stdout)
            guard snapshot.boot == session.boot else { throw CoreError("FX_ENTRY_MISMATCH") }
            try verify(ctx)
            return snapshot
        }
    }
    /// This path never starts FX, authenticates a new SSH connection or adds forwards.
    static func bind(_ params: [String: JSONValue], context: CoreContext,
                     emit: @escaping (String, String, [String: JSONValue]) -> Void) throws -> Bound {
        let request = try NativeCoreService.launchRequest(params, context: context, emit: emit, confirmed: false)
        let fx = try LaunchService.selectedFX(request)
        let transport = SSHTransport.make(request.configuration)
        guard transport.masterPID(context: context) != nil else { throw CoreError("SSH_DISCONNECTED") }
        let signature = try LaunchService.hostIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!, transport: transport, context: context, requireCDP: false, allowPublisherNetwork: true)
        let plan = try GuestService.inspect(transport, context: context)
        guard let boot = plan["boot"]?.text else { throw CoreError("FX_ENTRY_MISMATCH") }
        let endpoint = try LaunchService.endpointIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!, transport: transport, context: context)
        let digest = try CoreHash.sha256File(fx.appendingPathComponent("Contents/MacOS/steamac-vm"))
        let stable = CoreHash.sha256(Data([fx.resolvingSymlinksInPath().path, digest, endpoint, transport.settings.host,
            String(transport.settings.port), transport.settings.username, boot].joined(separator: "|").utf8))
        return Bound(transport: transport, session: GuestSession(boot: boot, identitySignature: signature, plan: plan), fx: fx, context: context, stableTarget: stable)
    }
    static func result(_ snapshot: GuestIPv6Snapshot, bound: Bound) -> [String: JSONValue] {
        ["status": .string(snapshot.status), "values": .object(snapshot.values.mapValues(JSONValue.string)),
         "guest_boot": .string(snapshot.boot), "fx_identity": .string(bound.receiptIdentity),
         "runtime_only": .bool(true), "observed_at": .string(CoreClock.stamp()), "can_modify": .bool(snapshot.valid),
         "scope": .string("four_runtime_sysctls_other_interfaces_preserved")]
    }
    static var receipts: URL { CoreFS.nativeData().appendingPathComponent("network-changes", isDirectory: true) }
    static func preview(_ bound: Bound, enabled: Bool?, backup: String? = nil) throws -> [String: JSONValue] {
        let snapshot = try bound.read(bound.context)
        guard snapshot.valid else { throw CoreError("UNSUPPORTED_CONFIGURATION") }
        let desired: [String: String]
        if let backup {
            let receipt = try load(backup)
            guard receipt["guest_boot"]?.text == snapshot.boot,
                  receipt["fx_identity"]?.text == bound.receiptIdentity,
                  let before = receipt["before"]?.object, let after = receipt["after"]?.object,
                  Set(before.keys) == Set(snapshot.values.keys), Set(after.keys) == Set(before.keys),
                  snapshot.values.allSatisfy({ before[$0.key]?.text == $0.value || after[$0.key]?.text == $0.value }) else { throw CoreError("CONFIG_CHANGED") }
            desired = before.compactMapValues(\.text)
        } else {
            guard let enabled else { throw CoreError("INVALID_ARGUMENT") }
            desired = snapshot.desired(enabled: enabled)
        }
        let desiredSnapshot = GuestIPv6Snapshot(boot: snapshot.boot, values: desired)
        guard desiredSnapshot.valid else { throw CoreError("UNSUPPORTED_CONFIGURATION") }
        var plan = result(snapshot, bound: bound)
        plan["operation"] = .string(backup == nil ? "set_guest_ipv6" : "restore_network_ipv6")
        plan["before"] = .object(snapshot.values.mapValues(JSONValue.string))
        plan["after"] = .object(desired.mapValues(JSONValue.string))
        if let backup { plan["backup_path"] = .string(backup) }
        plan["changed"] = .bool(desired != snapshot.values)
        return plan
    }
    static func load(_ path: String) throws -> [String: JSONValue] {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard url.deletingLastPathComponent() == receipts.standardizedFileURL,
              CoreFS.noSymlink(url), let data = try? Data(contentsOf: url), data.count < CoreLimits.maxSmallFile,
              let receipt = try? JSONDecoder().decode([String: JSONValue].self, from: data), receipt["version"]?.integer == 1 else {
            throw CoreError("UNTRUSTED_BACKUP")
        }
        return receipt
    }
    static func idle(_ bound: Bound, context: CoreContext) throws {
        if let idleProbe = bound.idleProbe { try idleProbe(context); return }
        let result = try bound.transport.run("command -v pgrep >/dev/null || exit 127\nif pgrep -x helldivers2.exe >/dev/null || pgrep -x reaper >/dev/null; then exit 75; fi\n", timeout: 5, context: context)
        guard result.status == 0 else { throw CoreError("GAME_ALREADY_RUNNING") }
    }
    static func apply(_ bound: Bound, plan: [String: JSONValue], password: String?, confirmed: Bool,
                      executor: ((GuestIPv6Snapshot, [String: String], CoreContext) throws -> Void)? = nil) throws -> [String: JSONValue] {
        guard confirmed else { throw CoreError("CONFIRMATION_REQUIRED") }
        let current = try bound.read(bound.context)
        guard current.valid, plan["guest_boot"]?.text == current.boot,
              plan["fx_identity"]?.text == bound.receiptIdentity,
              plan["before"]?.object == current.values.mapValues(JSONValue.string),
              let after = plan["after"]?.object, after.count == current.values.count else { throw CoreError("CONFIG_CHANGED") }
        let desired = after.compactMapValues(\.text)
        guard GuestIPv6Snapshot(boot: current.boot, values: desired).valid,
              Set(desired.keys) == Set(current.values.keys) else { throw CoreError("INVALID_ARGUMENT") }
        if desired == current.values { var unchanged = result(current, bound: bound); unchanged["changed"] = .bool(false); return unchanged }
        try idle(bound, context: bound.context)
        try CoreFS.ensurePrivateDirectory(receipts)
        let url = receipts.appendingPathComponent("ipv6-" + UUID().uuidString + ".json")
        var receipt: [String: JSONValue] = ["version": .number(1), "guest_boot": .string(current.boot),
            "fx_identity": .string(bound.receiptIdentity), "before": .object(current.values.mapValues(JSONValue.string)),
            "after": .object(desired.mapValues(JSONValue.string)), "status": .string("prepared")]
        func save() throws { try CoreFS.atomicWrite(Data(CoreJSON.pretty(.object(receipt)).utf8), to: url) }
        try save()
        func execute(_ snapshot: GuestIPv6Snapshot, _ values: [String: String], _ ctx: CoreContext) throws {
            if let executor { try executor(snapshot, values, ctx); return }
            _ = try GuestPrivilegedExecutor.run(bound.transport, operation: .networkIPv6(boot: snapshot.boot, before: snapshot.values, after: values),
                password: password, approved: true, context: ctx) { try bound.verify(ctx) }
        }
        do {
            try execute(current, desired, bound.context)
            let observed = try bound.read(bound.context)
            guard observed.values == desired else { throw CoreError("IPV6_VERIFY_FAILED") }
            receipt["status"] = .string("applied"); try save()
            var value = result(observed, bound: bound); value["backup_path"] = .string(url.path); value["changed"] = .bool(true)
            return value
        } catch {
            let failure = error as? CoreError ?? CoreError("IPV6_APPLY_FAILED")
            let recovery = CoreContext(timeout: 40)
            // Authentication/policy rejection cannot have started our fixed command.
            // Never retry a rejected password as a rollback, even if another actor changed values.
            if ["SUDO_AUTH_FAILED", "AUTH_REQUIRED", "SUDO_PERMISSION_DENIED", "SUDO_CREDENTIAL_INVALID", "CONFIG_CHANGED", "GAME_ALREADY_RUNNING"].contains(failure.code) {
                receipt["status"] = .string("not_applied"); try? save()
                let observed = try? bound.read(recovery)
                throw CoreError(failure.code, ["backup_path": .string(url.path),
                    "actual_values": observed.map { .object($0.values.mapValues(JSONValue.string)) } ?? .null])
            }
            var residual: GuestIPv6Snapshot?
            do {
                let observed = try bound.read(recovery)
                guard Set(observed.values.keys) == Set(current.values.keys), observed.values.allSatisfy({ current.values[$0.key] == $0.value || desired[$0.key] == $0.value }) else { throw CoreError("CONFIG_CHANGED") }
                if observed != current { try execute(observed, current.values, recovery) }
                let restored = try bound.read(recovery); residual = restored
                guard restored == current else { throw CoreError("IPV6_VERIFY_FAILED") }
                receipt["status"] = .string("rolled_back")
            } catch { receipt["status"] = .string("restore_required"); residual = try? bound.read(recovery) }
            if let residual { receipt["residual"] = .object(residual.values.mapValues(JSONValue.string)) }
            try? save()
            throw CoreError(failure.code, ["backup_path": .string(url.path), "recovery_status": receipt["status"]!,
                "actual_values": residual.map { .object($0.values.mapValues(JSONValue.string)) } ?? .null])
        }
    }
}
