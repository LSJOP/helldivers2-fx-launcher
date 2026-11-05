import Foundation

/// Lossless, bounded Valve KeyValues editor. Reject duplicate keys and unsupported syntax.
/// Writes are offline only: Steam must be closed, and files are backed up and CAS-guarded.
struct SteamVDF {
    struct Token { var text: String; var range: Range<String.Index>; var quoted: Bool }
    let source: String
    let tokens: [Token]
    init(_ source: String) throws {
        guard source.utf8.count <= CoreLimits.maxSmallFile else { throw CoreError("OUTPUT_LIMIT") }
        self.source = source
        var result: [Token] = [], i = source.startIndex
        while i < source.endIndex {
            if source[i].isWhitespace { i = source.index(after: i); continue }
            if source[i...].hasPrefix("//") { i = source[i...].firstIndex(of: "\n") ?? source.endIndex; continue }
            let start = i, ch = source[i]; i = source.index(after: i)
            if ch == "{" || ch == "}" { result.append(.init(text: String(ch), range: start..<i, quoted: false)); continue }
            guard ch == "\"" else { throw CoreError("VDF_CONFLICT") }
            var text = "", closed = false
            while i < source.endIndex {
                let c = source[i]; i = source.index(after: i)
                if c == "\"" { closed = true; break }
                if c == "\\" {
                    guard i < source.endIndex, ["\\", "\""].contains(source[i]) else { throw CoreError("VDF_CONFLICT") }
                    text.append(source[i]); i = source.index(after: i)
                } else { text.append(c) }
            }
            guard closed else { throw CoreError("VDF_CONFLICT") }
            result.append(.init(text: text, range: start..<i, quoted: true))
        }
        tokens = result
        _ = try fields() // Validate nesting/duplicates before any edit.
    }
    struct Field { let path: [String]; let value: Token?; let end: String.Index? }
    func fields() throws -> [Field] {
        var i = 0, result: [Field] = []
        func parse(_ path: [String], depth: Int) throws {
            guard depth < 32 else { throw CoreError("VDF_CONFLICT") }
            var seen = Set<String>()
            while i < tokens.count && tokens[i].text != "}" {
                let key = tokens[i]; i += 1
                guard key.quoted, seen.insert(key.text.lowercased()).inserted, i < tokens.count else { throw CoreError("VDF_CONFLICT") }
                let full = path + [key.text.lowercased()]
                if !tokens[i].quoted && tokens[i].text == "{" {
                    i += 1; try parse(full, depth: depth + 1)
                    guard i < tokens.count, tokens[i].text == "}", !tokens[i].quoted else { throw CoreError("VDF_CONFLICT") }
                    result.append(.init(path: full, value: nil, end: tokens[i].range.lowerBound)); i += 1
                } else {
                    guard tokens[i].quoted else { throw CoreError("VDF_CONFLICT") }
                    result.append(.init(path: full, value: tokens[i], end: nil)); i += 1
                }
            }
        }
        try parse([], depth: 0)
        guard i == tokens.count else { throw CoreError("VDF_CONFLICT") }
        return result
    }
    func value(_ path: [String]) throws -> String? { try fields().first { $0.path == path.map { $0.lowercased() } }?.value?.text }
    static func quote(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    func setting(_ path: [String], value: String) throws -> String {
        guard !path.isEmpty, !value.contains("\n"), !value.contains("\r") else { throw CoreError("VDF_CONFLICT") }
        let all = try fields(), target = path.map { $0.lowercased() }
        if let token = all.first(where: { $0.path == target })?.value {
            var changed = source; changed.replaceSubrange(token.range, with: Self.quote(value)); return changed
        }
        guard let end = all.first(where: { $0.path == Array(target.dropLast()) })?.end else { throw CoreError("VDF_CONFLICT") }
        var changed = source; changed.insert(contentsOf: "\n\t" + Self.quote(path.last!) + "\t" + Self.quote(value) + "\n", at: end)
        return changed
    }
    func removing(_ path: [String]) throws -> String {
        guard let token = try fields().first(where: { $0.path == path.map { $0.lowercased() } })?.value,
              let i = tokens.firstIndex(where: { $0.range == token.range }), i > 0 else { return source }
        var changed = source; changed.removeSubrange(tokens[i-1].range.lowerBound..<token.range.upperBound); return changed
    }
    static let launchPath = ["userlocalconfigstore", "software", "valve", "steam", "apps", "553850", "launchoptions"]
    static let toolPath = ["installconfigstore", "software", "valve", "steam", "compattoolmapping", "553850", "name"]
}

final class SSHEnvironmentBackend: DeploymentBackend {
    let transport: SSHTransport, fx: URL, context: CoreContext, configurationRevision: String
    var expectedGuestBoot: String?
    let fxVersion: String
    var sudoPassword: String? // Memory only; never included in a snapshot or receipt.
    private var documents: [String: String] = [:]
    private var paths: [String: String] = [:]
    init(fx: URL, transport: SSHTransport, context: CoreContext, revision: String) throws {
        self.fx = fx; self.transport = transport; self.context = context; configurationRevision = revision
        guard let identity = FXDiscoveryService.identity(of: fx.path), identity.valid else { throw CoreError("FX_ENTRY_MISMATCH") }
        fxVersion = identity.version
    }
    func hostIdentity() throws -> String {
        guard try ConfigurationService.read().revision == configurationRevision else { throw CoreError("CONFIG_CHANGED") }
        let resources = try LaunchResources.verifiedForLaunch()
        return try LaunchService.hostIdentity(fx: fx, gvproxy: resources.binary, transport: transport,
                                             context: context, requireCDP: false, allowPublisherNetwork: true)
    }
    /// The authenticated master is verified for every probe, but its transient PID is
    /// excluded from the plan identity so a separately authenticated action can apply it.
    /// FX/network process identities, peer, selected path and Guest boot remain bound.
    static func deploymentBinding(_ signature: String, fxPath: String) throws -> String {
        let fields = signature.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard fields.count == 5, Int(fields[0]) != nil, Int(fields[2]) != nil,
              !fields[1].isEmpty, !fields[3].isEmpty, !fields[4].isEmpty else { throw CoreError("TARGET_CHANGED") }
        let stable = [fxPath, fields[0], fields[1], fields[3], fields[4]].joined(separator: "|")
        return CoreHash.sha256(Data(stable.utf8))
    }
    func snapshot() throws -> DeploymentSnapshot {
        let identity = try hostIdentity()
        let result = try transport.run(Self.probe, timeout: 40, context: context)
        guard result.status == 0 else { throw CoreError("ENVIRONMENT_DETECTION_FAILED") }
        var fields: [String: String] = [:]
        for line in result.stdout.split(separator: "\n") {
            let row = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard row.count == 2, fields[String(row[0])] == nil else { throw CoreError("ENVIRONMENT_DETECTION_FAILED") }
            fields[String(row[0])] = String(row[1])
        }
        guard let boot = fields["boot"], UUID(uuidString: boot) != nil, fields["os"] == "steamos",
              fields["user"] == transport.settings.username, let free = fields["free"].flatMap(Int64.init),
              let sp = fields["steam_count"].flatMap(Int.init), let gp = fields["game_count"].flatMap(Int.init),
              try hostIdentity() == identity else { throw CoreError("TARGET_CHANGED") }
        if let expectedGuestBoot, boot != expectedGuestBoot { throw CoreError("CREDENTIAL_SCOPE_CHANGED") }
        documents = [:]; paths = [:]
        var values: [String: String] = [:], facts = fields
        for (key, vdfPath) in [("launch", SteamVDF.launchPath), ("tool", SteamVDF.toolPath)] {
            if let raw = fields[key + "_data"], let data = Data(base64Encoded: raw), let doc = String(data: data, encoding: .utf8),
               let parsed = try? SteamVDF(doc), let current = try? parsed.value(vdfPath) {
                documents[key] = doc; paths[key] = fields[key + "_path"]; values[key] = current; values[key + "_present"] = "true"
            } else if let raw = fields[key + "_data"], let data = Data(base64Encoded: raw), let doc = String(data: data, encoding: .utf8),
                      let parsed = try? SteamVDF(doc), (try? parsed.setting(vdfPath, value: "")) != nil {
                documents[key] = doc; paths[key] = fields[key + "_path"]; values[key] = ""; values[key + "_present"] = "false"
            } else { facts[key] = "UNKNOWN" }
            facts.removeValue(forKey: key + "_data"); facts.removeValue(forKey: key + "_path")
        }
        // FEX remains unapproved. Proton readiness is limited to the exact pinned release
        // and critical-file hashes checked by the bounded Guest probe.
        facts["fex_manifest"] = "UNKNOWN"
        facts["proton_manifest"] = fields["proton_manifest"] ?? "UNKNOWN"
        values["component.proton"] = fields["proton_component"] ?? "UNKNOWN"
        for (key, value) in fields where key.hasPrefix("net6_") { values["ipv6." + key.dropFirst(5)] = value }
        facts["network"] = "UNKNOWN" // A default route is not Steam/game reachability.
        let pref = try? CFPreferencesStore(domain: PerformanceDomain.name).read()
        for key in ["cpus", "memMiB", "gpuMemMiB", "graphicsPath", "vulkanDriver", "metalHUD", "superResolution"] {
            facts["fx_" + key] = pref?[key].map { CoreJSON.encode($0) } ?? "UNKNOWN"
        }
        let revisionFields = fields.filter { !$0.key.hasSuffix("_count") && !["free"].contains($0.key) }
        let revision = CoreHash.sha256(Data((CoreJSON.encode(.object(revisionFields.mapValues { .string($0) })) + configurationRevision).utf8))
        return .init(target: try Self.deploymentBinding(identity, fxPath: fx.path), boot: boot, revision: revision, fxVersion: fxVersion,
                     osVersion: fields["os_version"] ?? "UNKNOWN", architecture: fields["arch"] ?? "UNKNOWN",
                     steamRunning: sp > 0, gameRunning: gp > 0 || (fields["reaper_count"].flatMap(Int.init) ?? 1) > 0, freeBytes: free, facts: facts, values: values)
    }
    func replace(_ changes: [String: String], expected: DeploymentSnapshot) throws {
        if !changes.isEmpty && changes.keys.allSatisfy({ $0.hasPrefix("ipv6.") }) { try replaceIPv6(changes, expected: expected); return }
        if Set(changes.keys) == ["component.proton"] {
            try replaceProton(changes["component.proton"]!, expected: expected); return
        }
        guard let key = changes.keys.first(where: { ["launch", "tool"].contains($0) }), Set(changes.keys).isSubset(of: [key, key + "_present"]) else { throw CoreError("INVALID_ARGUMENT") }
        let current = try snapshot()
        guard EnvironmentDeploymentService.identity(current, expected), current.revision == expected.revision else { throw CoreError("CONFIG_CHANGED") }
        try EnvironmentDeploymentService.idle(current)
        guard let original = documents[key], let path = paths[key], let after = changes[key],
              path.range(of: "^[A-Za-z0-9_./ -]+$", options: .regularExpression) != nil,
              !CoreRedaction.containsSecret(after) else { throw CoreError("VDF_CONFLICT") }
        let valuePath = key == "launch" ? SteamVDF.launchPath : SteamVDF.toolPath
        let edited = changes[key + "_present"] == "false" ? try SteamVDF(original).removing(valuePath) : try SteamVDF(original).setting(valuePath, value: after)
        let encoded = Data(edited.utf8).base64EncodedString(), digest = CoreHash.sha256(Data(original.utf8))
        let boot = expected.boot, quoted = Self.quote(path)
        // A guest-side lock, boot check, running-process check, symlink walk, and full-file
        // digest protect the actual destination. No Steam/VM process is stopped.
        let script = """
        set -eu
        umask 077
        p=\(quoted)
        lock="$HOME/.hd2-native-deployment-lock"
        mkdir "$lock" || exit 70
        tmp=''
        trap '[ -z "$tmp" ] || rm -f "$tmp"; rmdir "$lock"' EXIT
        [ "$(cat /proc/sys/kernel/random/boot_id)" = '\(boot)' ] || exit 71
        for n in steam reaper helldivers2.exe; do
          if pgrep -x "$n" >/dev/null; then exit 72; else [ "$?" -eq 1 ] || exit 72; fi
        done
        walk="$p"
        while [ "$walk" != / ]; do [ ! -L "$walk" ] || exit 73; walk=$(dirname "$walk"); done
        [ "$(sha256sum "$p" | cut -d' ' -f1)" = '\(digest)' ] || exit 74
        backup="$p.hd2-native-\(UUID().uuidString).backup"
        cp -p "$p" "$backup"
        tmp=$(mktemp "$p.hd2-stage.XXXXXXXX")
        printf '%s' '\(encoded)' | base64 -d > "$tmp"
        chmod --reference="$p" "$tmp"
        [ "$(sha256sum "$p" | cut -d' ' -f1)" = '\(digest)' ] || exit 74
        mv "$tmp" "$p"
        tmp=''
        [ "$(sha256sum "$p" | cut -d' ' -f1)" = '\(CoreHash.sha256(Data(edited.utf8)))' ] || exit 75
        """
        _ = try hostIdentity()
        let result = try transport.run(script, timeout: 30, context: context)
        guard result.status == 0 else { throw CoreError("CONFIGURATION_TRANSACTION_FAILED") }
    }
    static func quote(_ text: String) -> String { "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static let probe = #"""
set -eu
S="$HOME/.local/share/Steam"
printf 'boot=%s\nuser=%s\narch=%s\n' "$(cat /proc/sys/kernel/random/boot_id)" "$(id -un)" "$(uname -m)"
os=$(sed -n 's/^ID=//p' /etc/os-release | tr -d '"')
os_version=$(sed -n 's/^VERSION_ID=//p' /etc/os-release | tr -d '"')
printf 'os=%s\nos_version=%s\n' "$os" "$os_version"
for n in steam helldivers2.exe reaper; do
  count=$(pgrep -x "$n" | wc -l) || exit 2
  case "$n" in steam) printf 'steam_count=%s\n' "$(echo "$count" | tr -d ' ')";; helldivers2.exe) printf 'game_count=%s\n' "$(echo "$count" | tr -d ' ')";; reaper) printf 'reaper_count=%s\n' "$(echo "$count" | tr -d ' ')";; esac
done
free=$(df -Pk "$HOME" | awk 'NR==2 {printf "%.0f", $4*1024}')
printf 'free=%s\n' "$free"
present(){ if [ -e "$2" ]; then printf '%s=present\n' "$1"; else printf '%s=missing\n' "$1"; fi; }
present steam "$S/steam.sh"
present game "$S/steamapps/common/Helldivers 2/bin/helldivers2.exe"
# Bounded file discovery only: do not run unknown FEX/Proton executables.
fex_found=missing
for f in "$S/steamapps/common/FEX-Emu/usr/bin/FEX" "$S/steamapps/common/FEX-Emu/usr/bin/FEXInterpreter" /usr/bin/FEX /usr/bin/FEXInterpreter /usr/local/bin/FEXInterpreter; do
 if [ -f "$f" ]; then fex_found=present; fi
done
printf 'fex=%s\n' "$fex_found"
proton_found=missing
for root in "$S/compatibilitytools.d" "$HOME/.steam/compatibilitytools.d"; do
 count=0
 for d in "$root"/*; do
  [ -d "$d" ] || continue
  count=$((count+1)); [ "$count" -le 64 ] || { proton_found=UNKNOWN; break; }
  name=$(basename "$d")
  case "$name" in *[Pp][Rr][Oo][Tt][Oo][Nn]*[Jj][Ee]*)
   if [ -f "$d/proton" ] && [ -f "$d/compatibilitytool.vdf" ]; then proton_found=present; fi;;
  esac
 done
done
printf 'proton=%s\n' "$proton_found"
proton_target="$S/compatibilitytools.d/proton-je-11.0-20261014-3"
proton_component=missing
proton_manifest=UNKNOWN
if [ -d "$proton_target" ] && [ ! -L "$proton_target" ]; then
 proton_component=unverified
 if [ "$(sha256sum "$proton_target/proton" 2>/dev/null | cut -d' ' -f1)" = 4d8392f0ec4adebed83513589f4be30ad6a9c669230a94724a18dff0acdd203a ] &&
    [ "$(sha256sum "$proton_target/compatibilitytool.vdf" 2>/dev/null | cut -d' ' -f1)" = 43a068c09d826c90c2a67147293a58b8289244cb34302cda89f19b8e6f0b0eaa ] &&
    [ "$(sha256sum "$proton_target/toolmanifest.vdf" 2>/dev/null | cut -d' ' -f1)" = bb81d44a687cc6f4ea7ae05fa9f0502f35c48e462051809dce3b2a58492e3498 ] &&
    [ "$(sha256sum "$proton_target/files/lib/wine/x86_64-windows/ntdll.dll" 2>/dev/null | cut -d' ' -f1)" = a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe ]; then
   proton_component=a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe
   proton_manifest=verified
 fi
fi
printf 'proton_component=%s\nproton_manifest=%s\n' "$proton_component" "$proton_manifest"
for pair in 'fex:FEX-Emu/usr/bin/FEX'; do
 f="$S/steamapps/common/${pair#*:}"; if [ -f "$f" ]; then printf 'fex_sha256=%s\n' "$(sha256sum "$f" | cut -d' ' -f1)"; fi
done
if grep -qw 'steamac.gfx=vulkan' /proc/cmdline; then printf 'vulkan=configured\n'; else printf 'vulkan=UNKNOWN\n'; fi
printf 'kosmickrisp=UNKNOWN\ngvproxy=available\n'
for file in /proc/sys/net/ipv6/conf/*/disable_ipv6; do
 [ -f "$file" ] || continue
 name=$(basename "$(dirname "$file")")
 printf 'net6_%s=%s\n' "$name" "$(cat "$file")"
done
for family in ipv4 ipv6; do
 if [ "$family" = ipv4 ]; then ip -4 route show default | head -1 | sed 's/.*/ipv4=available/'; else
   for k in all default eth0 lo; do
    printf 'ipv6_%s=%s\n' "$k" "$(cat "/proc/sys/net/ipv6/conf/$k/disable_ipv6" 2>/dev/null || printf UNKNOWN)"
   done
 fi
done
if [ -d "$S" ]; then
 for kind in launch tool; do
  if [ "$kind" = tool ]; then set -- "$S/config/config.vdf"; else set -- "$S"/userdata/*/config/localconfig.vdf; fi
  if [ "$#" = 1 ] && [ -f "$1" ] && [ ! -L "$1" ]; then
   [ "$(wc -c < "$1")" -le 262144 ] || exit 3
   printf '%s_path=%s\n' "$kind" "$1"
   printf '%s_data=' "$kind"; base64 < "$1" | tr -d '\n'; printf '\n'
  fi
 done
fi
"""#
}

/// FX writes reuse the audited version/hardware bounds, stopped-VM guard, scoped backup,
/// preview token and readback. No historical CPU/RAM/GPU values are forced by setup.
enum GraphicsConfigurationAdapter {
    static func inspect(app: URL) throws -> [String: JSONValue] {
        let rules = try PerformanceConfigurationService.capabilities(app: app)
        var result = try PerformanceConfigurationService.snapshot(store: CFPreferencesStore(domain: PerformanceDomain.name), rules: rules)
        result["hardware"] = .object(SystemProbe.hardware()); return result
    }
    static func apply(app: URL, values: [String: JSONValue], revision: String, token: String) throws -> [String: JSONValue] {
        let rules = try PerformanceConfigurationService.capabilities(app: app)
        return try PerformanceConfigurationService.commit(values: values, revision: revision, token: token, restore: false,
            store: CFPreferencesStore(domain: PerformanceDomain.name), rules: rules) { _ in }
    }
}

/// Network candidates are never automatically folded into the approved base plan.
/// This adapter produces reversible per-interface changes only for a separately approved
/// profile and an exact interface snapshot. Host global IPv6 is outside this API.
enum NetworkConfigurationAdapter {
    static func ipv4Plan(current: [String: String], profileAllows: Bool, consent: Bool) throws -> [String: String] {
        guard profileAllows, consent, !current.isEmpty, current.allSatisfy({ key, value in
            key.range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil && ["0", "1"].contains(value)
        }) else { throw CoreError("PROFILE_NOT_APPLICABLE") }
        return current.mapValues { _ in "1" }
    }
}

extension NativeCoreService {
    static var deploymentReceipts: DeploymentReceiptStore {
        DeploymentReceiptStore(directory: CoreFS.nativeData().appendingPathComponent("environment-deployments", isDirectory: true))
    }
    static func deployment(_ method: String, params: [String: JSONValue], context: CoreContext,
                           emit: @escaping (String, String, [String: JSONValue]) -> Void) throws -> [String: JSONValue] {
        func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
        if method == "first_run_receipts" { return ["receipts": try json(deploymentReceipts.list())] }
        let request = try launchRequest(params, context: context, emit: emit, confirmed: true)
        let fx = try LaunchService.selectedFX(request)
        let integrity = FXDiscoveryService.integrity(app: fx, context: context)
        guard FXDiscoveryService.launchAllowed(integrity) else {
            throw CoreError("FX_ENTRY_MISMATCH", ["integrity_state": integrity["state"] ?? .string("unverified")])
        }
        let transport = SSHTransport.isolatedSetup(request.configuration)
        defer { transport.closeMaster() }
        guard SSHTransport.localHost(transport.settings.host) else { throw CoreError("LOCAL_FX_REQUIRED") }
        _ = try LaunchService.endpointIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!, transport: transport, context: context)
        transport.setSecret(password: request.password, passphrase: request.passphrase)
        try transport.connectOnce(context: context, forwarding: false)
        let backend = try SSHEnvironmentBackend(fx: fx, transport: transport, context: context, revision: ConfigurationService.read().revision)
        backend.sudoPassword = request.sudoPassword
        backend.expectedGuestBoot = params["credential_guest_boot"]?.text
        let service = EnvironmentDeploymentService(backend: backend, receipts: deploymentReceipts)
        if method == "first_run_detect" {
            let snapshot = try backend.snapshot()
            if transport.passwordWasSent {
                emit("INFO", "SSH authenticated", ["kind": .string("credential_status"), "credential_kind": .string("ssh"), "status": .string("authenticated")])
            }
            let plan = DeploymentPlanBuilder.build(snapshot, profile: try EnvironmentProfile.bundled())
            return ["plan": try json(plan), "ssh_password_verified": .bool(transport.passwordWasSent)]
        }
        if method == "first_run_deploy" {
            guard let raw = params["deployment_plan"] else { throw CoreError("INVALID_ARGUMENT") }
            let plan = try JSONDecoder().decode(DeploymentPlan.self, from: JSONEncoder().encode(raw))
            let policy = try EnvironmentProfile.bundled()
            let actual = try backend.snapshot()
            guard actual.values == plan.snapshot.values else { throw CoreError("CONFIG_CHANGED") }
            let rebuilt = DeploymentPlanBuilder.build(actual, profile: policy)
            guard plan.operations == rebuilt.operations, plan.profileID == policy.id, plan.profileVersion == policy.version else { throw CoreError("PROFILE_INVALID") }
            let receipt = try service.execute(plan, approved: Set(params["approved_steps"]?.array.compactMap(\.text) ?? []), context: context) { status in
                emit("INFO", "Environment deployment", ["deployment_state": .string(status.rawValue)])
            }
            return ["receipt": try json(receipt)]
        }
        if method == "first_run_recover" {
            guard let id = params["receipt_id"]?.text.flatMap(UUID.init(uuidString:)) else { throw CoreError("INVALID_ARGUMENT") }
            return ["receipt": try json(service.recover(id, selected: Set(params["approved_steps"]?.array.compactMap(\.text) ?? [])))]
        }
        throw CoreError("INVALID_ARGUMENT")
    }
}


extension SSHEnvironmentBackend {
    private static let protonVersion = "proton-je-11.0-20261014-3"
    private static let protonURL = "https://github.com/jegglest/proton-je/releases/download/proton-je-11.0-20261014-3/proton-je-11.0-20261014-3.tar.xz"
    private static let protonArchiveHash = "aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485"
    private static let protonNTDLLHash = "a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe"

    /// Install or roll back only the exact reviewed Proton release. The pinned archive hash
    /// authenticates the complete tar.xz bytes; extraction is confined to a private stage,
    /// rejects special files and escaping links, and the final move is atomic.
    func replaceProton(_ desired: String, expected: DeploymentSnapshot) throws {
        let live = try snapshot()
        guard EnvironmentDeploymentService.identity(live, expected), live.revision == expected.revision else { throw CoreError("CONFIG_CHANGED") }
        try EnvironmentDeploymentService.idle(live)
        guard live.fxVersion == "1.9.4", live.osVersion == "0.4.5", live.architecture == "aarch64" else { throw CoreError("BASELINE_UNAVAILABLE") }
        let profile = try EnvironmentProfile.bundled()
        guard let artifact = profile.artifacts.first(where: { $0.component == "proton" && $0.version == Self.protonVersion }),
              artifact.source == Self.protonURL, artifact.archiveSHA256 == Self.protonArchiveHash,
              artifact.files["files/lib/wine/x86_64-windows/ntdll.dll"] == Self.protonNTDLLHash else { throw CoreError("ARTIFACT_UNAPPROVED") }
        let script: String
        if desired == Self.protonNTDLLHash {
            guard live.values["component.proton"] == "missing" else { throw CoreError("COMPONENT_CONFLICT") }
            script = Self.protonInstallScript(boot: live.boot)
        } else if desired == "missing" {
            guard live.values["component.proton"] == Self.protonNTDLLHash else { throw CoreError("EXTERNAL_DRIFT") }
            script = Self.protonRollbackScript(boot: live.boot, suffix: UUID().uuidString)
        } else { throw CoreError("ARTIFACT_UNAPPROVED") }
        _ = try hostIdentity()
        let result = try transport.run(script, timeout: desired == "missing" ? 90 : 1_200, context: context)
        guard result.status == 0 else { throw CoreError(desired == "missing" ? "RECOVERY_REQUIRED" : "COMPONENT_INSTALL_FAILED") }
    }

    static func protonInstallScript(boot: String) -> String {
        """
        set -eu
        umask 077
        S="$HOME/.local/share/Steam"
        p="$S/compatibilitytools.d/\(protonVersion)"
        cache="$HOME/.cache/hd2-native"
        lock="$HOME/.hd2-native-deployment-lock"
        mkdir "$lock" || exit 80
        work=''
        cleanup(){ case "$work" in "$cache"/proton-stage.*) rm -rf -- "$work";; '') :;; *) exit 87;; esac; rmdir "$lock"; }
        trap cleanup EXIT HUP INT TERM
        [ "$(cat /proc/sys/kernel/random/boot_id)" = '\(boot)' ] || exit 81
        for n in steam reaper helldivers2.exe; do if pgrep -x "$n" >/dev/null; then exit 81; else [ "$?" -eq 1 ] || exit 81; fi; done
        walk="$p"; while [ "$walk" != / ]; do [ ! -L "$walk" ] || exit 81; walk=$(dirname "$walk"); done
        [ ! -e "$p" ] || exit 82
        mkdir -p "$cache"
        [ -d "$cache" ] && [ ! -L "$cache" ] || exit 82
        chmod 700 "$cache"
        work=$(mktemp -d "$cache/proton-stage.XXXXXXXX")
        archive="$work/archive.tar.xz"
        curl --fail --show-error --silent --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
          --connect-timeout 15 --max-time 900 --speed-time 30 --speed-limit 1024 \
          --max-filesize 348245820 --output "$archive" '\(protonURL)'
        [ "$(wc -c < "$archive" | tr -d ' ')" = 348245820 ] || exit 83
        [ "$(sha256sum "$archive" | cut -d' ' -f1)" = '\(protonArchiveHash)' ] || exit 83
        mkdir "$work/unpack"
        tar --extract --xz --file "$archive" --directory "$work/unpack" --no-same-owner --no-same-permissions
        stage="$work/unpack/\(protonVersion)"
        [ -d "$stage" ] && [ ! -L "$stage" ] || exit 84
        [ "$(find "$work/unpack" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')" = 1 ] || exit 84
        [ "$(find "$stage" -type f | wc -l | tr -d ' ')" = 5609 ] || exit 84
        [ "$(find "$stage" -type l | wc -l | tr -d ' ')" = 1896 ] || exit 84
        [ -z "$(find "$stage" ! -type d ! -type f ! -type l -print -quit)" ] || exit 84
        find "$stage" -type l -exec sh -c 'root=$1; shift; for link do resolved=$(realpath -m -- "$link") || exit 1; case "$resolved" in "$root"/*) :;; *) exit 1;; esac; done' sh "$stage" {} + || exit 84
        [ "$(sha256sum "$stage/proton" | cut -d' ' -f1)" = 4d8392f0ec4adebed83513589f4be30ad6a9c669230a94724a18dff0acdd203a ] || exit 85
        [ "$(sha256sum "$stage/compatibilitytool.vdf" | cut -d' ' -f1)" = 43a068c09d826c90c2a67147293a58b8289244cb34302cda89f19b8e6f0b0eaa ] || exit 85
        [ "$(sha256sum "$stage/toolmanifest.vdf" | cut -d' ' -f1)" = bb81d44a687cc6f4ea7ae05fa9f0502f35c48e462051809dce3b2a58492e3498 ] || exit 85
        [ "$(sha256sum "$stage/files/lib/wine/x86_64-windows/ntdll.dll" | cut -d' ' -f1)" = '\(protonNTDLLHash)' ] || exit 85
        [ "$(cat /proc/sys/kernel/random/boot_id)" = '\(boot)' ] || exit 81
        for n in steam reaper helldivers2.exe; do if pgrep -x "$n" >/dev/null; then exit 81; else [ "$?" -eq 1 ] || exit 81; fi; done
        [ ! -e "$p" ] || exit 82
        mkdir -p "$(dirname "$p")"
        mv "$stage" "$p"
        [ "$(sha256sum "$p/files/lib/wine/x86_64-windows/ntdll.dll" | cut -d' ' -f1)" = '\(protonNTDLLHash)' ] || exit 86
        """
    }

    static func protonRollbackScript(boot: String, suffix: String) -> String {
        """
        set -eu
        p="$HOME/.local/share/Steam/compatibilitytools.d/\(protonVersion)"
        retained="$p.hd2-recovered-\(suffix)"
        lock="$HOME/.hd2-native-deployment-lock"
        mkdir "$lock" || exit 80
        trap 'rmdir "$lock"' EXIT HUP INT TERM
        [ "$(cat /proc/sys/kernel/random/boot_id)" = '\(boot)' ] || exit 81
        for n in steam reaper helldivers2.exe; do if pgrep -x "$n" >/dev/null; then exit 81; else [ "$?" -eq 1 ] || exit 81; fi; done
        [ -d "$p" ] && [ ! -L "$p" ] && [ ! -e "$retained" ] || exit 82
        [ "$(sha256sum "$p/files/lib/wine/x86_64-windows/ntdll.dll" | cut -d' ' -f1)" = '\(protonNTDLLHash)' ] || exit 82
        mv "$p" "$retained"
        [ ! -e "$p" ] || exit 83
        """
    }

    /// Only the exact Guest interface set is writable. Linux conf/all cascades, so all
    /// interfaces (including originally unchanged ones) must be in both plan and receipt.
    func replaceIPv6(_ changes: [String: String], expected: DeploymentSnapshot) throws {
        let current = try snapshot()
        guard EnvironmentDeploymentService.identity(current, expected), current.revision == expected.revision else { throw CoreError("CONFIG_CHANGED") }
        try EnvironmentDeploymentService.idle(current)
        let originals = current.values.filter { $0.key.hasPrefix("ipv6.") }
        guard !originals.isEmpty, Set(changes.keys) == Set(originals.keys), changes.allSatisfy({ key, value in
            String(key.dropFirst(5)).range(of: "^[A-Za-z0-9_.:-]+$", options: .regularExpression) != nil && ["0", "1"].contains(value)
        }) else { throw CoreError("PROFILE_NOT_APPLICABLE") }
        let before = Dictionary(uniqueKeysWithValues: originals.map { (String($0.key.dropFirst(5)), $0.value) })
        let after = Dictionary(uniqueKeysWithValues: changes.map { (String($0.key.dropFirst(5)), $0.value) })
        _ = try GuestPrivilegedExecutor.run(transport,
            operation: .networkIPv6(boot: current.boot, before: before, after: after),
            password: sudoPassword, approved: true, context: context) {
                let live = try self.snapshot()
                guard EnvironmentDeploymentService.identity(live, current) else { throw CoreError("TARGET_CHANGED") }
                try EnvironmentDeploymentService.idle(live)
            }
    }
}
