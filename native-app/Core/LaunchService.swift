import Foundation

/// Native host/FX/Guest launch orchestration. Each stage is evidence, never a claim of
/// gameplay: process existence is reported separately from main-menu or multiplayer state.
struct LaunchRequest {
    var configuration: [String: JSONValue]
    var fxPath: String
    var password: String?
    var passphrase: String?
    var sudoPassword: String?
    var approvedChanges: [JSONValue]
    var context: CoreContext
    var emit: (String, String, [String: JSONValue]) -> Void
}

enum LaunchService {
    static let requiredLaunchTokens = ["FEX_DISKCACHE=0", "FEX_NEEDSSECCOMP=1", "PROTON_USE_XALIA=0", "VKD3D_CONFIG=single_queue"]
    static let verifiedFEX = "ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf"
    static let verifiedNTDLL = "a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe"
    static let verifiedTool = "proton-je-11.0-20261014-3"
    static let verifiedWine: [String: String] = [
        "x86_64-windows/user32.dll": "e51cd4a5e451b5bf6c2f89582bd1b341bfec9309c468bed5ed5f49d3dd5c7e09",
        "x86_64-windows/win32u.dll": "1bfc85f5aacb14b405794bbe82cbf733eb7f09701697aa2300dbb9e22a123a92",
        "x86_64-windows/kernelbase.dll": "1c4eb48f08594541605e31391835b5d150a4bf46691236df7896cda51001b5b8",
        "x86_64-unix/win32u.so": "05a159f75fb302bfe3c67386a6d17b53f4db521e0726281a8dad7121006e627c"]

    static var lockURL: URL {
        URL(fileURLWithPath: "/tmp/hd2fx-targets-\(getuid())", isDirectory: true).appendingPathComponent("fx-launch.lock")
    }

    static func selectedFX(_ request: LaunchRequest) throws -> URL {
        guard !request.fxPath.isEmpty else { throw CoreError("FX_UNAVAILABLE") }
        guard let identity = FXDiscoveryService.identity(of: request.fxPath), identity.valid else { throw CoreError("FX_UNAVAILABLE") }
        return URL(fileURLWithPath: identity.path)
    }

    static func fxVersion(_ app: URL) -> String { DependencyProbe.bundleVersion(app) ?? "unknown" }

    // MARK: - Host process identity

    struct ProcessRow { let pid: Int; let ppid: Int; let start: String; let command: String }

    static func processTable(context: CoreContext?) throws -> [Int: ProcessRow] {
        parseProcessTable(try CoreProcess.psCommandTable(context: context))
    }

    /// Pure parser for `ps -ww -axo pid=,ppid=,lstart=,comm=`; kept separate for testing.
    static func parseProcessTable(_ text: String) -> [Int: ProcessRow] {
        var rows: [Int: ProcessRow] = [:]
        for line in text.split(separator: "\n") {
            // `ps` right-aligns columns, so the command field carries leading padding;
            // split at most 7 times (pid, ppid, 5 lstart tokens) and trim the remainder.
            let fields = line.split(separator: " ", maxSplits: 7, omittingEmptySubsequences: true)
            guard fields.count == 8, let pid = Int(fields[0]), let ppid = Int(fields[1]) else { continue }
            let start = fields[2..<7].joined(separator: " ")
            let command = String(fields[7]).trimmingCharacters(in: .whitespaces)
            rows[pid] = ProcessRow(pid: pid, ppid: ppid, start: start, command: command)
        }
        return rows
    }

    /// Canonical executable path: resolves symlinks and standardizes, so the same FX
    /// bundle reached through a symlink or App Translocation is not misread as foreign.
    static func normalizedExecutable(_ fx: URL) -> String {
        fx.appendingPathComponent("Contents/MacOS/steamac-vm")
            .resolvingSymlinksInPath().standardizedFileURL.path
    }
    static func normalizedCommand(_ command: String) -> String {
        URL(fileURLWithPath: command).resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// FX legitimately runs as one supervisor plus one direct VM child (both share the
    /// same executable path). Normalize that topology to the supervisor PID; anything
    /// else stays unverified.
    static func fxSupervisorPID(rows: [Int: ProcessRow], executable: String) throws -> Int {
        let matches = rows.values.filter { normalizedCommand($0.command) == executable }.map(\.pid).sorted()
        switch matches.count {
        case 1: return matches[0]
        case 2:
            let children = matches.filter { pid in
                guard let row = rows[pid] else { return false }
                return matches.contains(row.ppid)
            }
            guard children.count == 1 else {
                throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("fx_topology_unverified")])
            }
            let child = children[0]
            let parent = rows[child]!.ppid
            guard matches.contains(parent), rows[parent]?.ppid != child else {
                throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("fx_topology_unverified")])
            }
            return parent
        case 0:
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("selected_fx_not_running")])
        default:
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("duplicate_fx_processes")])
        }
    }

    /// steamac-vm processes whose canonical executable path differs from the selected FX.
    static func foreignProcesses(rows: [Int: ProcessRow], executable: String) -> [ProcessRow] {
        rows.values.filter {
            URL(fileURLWithPath: normalizedCommand($0.command)).lastPathComponent == "steamac-vm"
                && normalizedCommand($0.command) != executable
        }
    }

    static func hostIdentity(fx: URL, gvproxy: URL, transport: SSHTransport, context: CoreContext?) throws -> String {
        let rows = try processTable(context: context)
        let executable = normalizedExecutable(fx)
        let fxPID = try fxSupervisorPID(rows: rows, executable: executable)
        func belongs(_ pid: Int) -> Bool {
            var seen = Set<Int>(); var current = pid
            while let row = rows[current], !seen.contains(current) {
                if current == fxPID { return true }
                seen.insert(current); current = row.ppid
            }
            return false
        }
        let network = rows.values.filter { $0.command == gvproxy.path && belongs($0.pid) }
        guard !network.isEmpty else { throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("gvproxy_not_child_of_fx")]) }
        let listeners = try fileDescriptors(arguments: ["-nP", "-iTCP:\(transport.settings.port)", "-sTCP:LISTEN", "-Fpn"], context: context)
        let owners = listeners.compactMap { pid, names in names.contains { $0.hasSuffix(":\(transport.settings.port)") } ? pid : nil }
        guard !owners.isEmpty, owners.allSatisfy({ belongs($0) }) else {
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("ssh_listener_not_owned_by_fx")])
        }
        guard let master = transport.masterPID(context: context), let masterRow = rows[master],
              URL(fileURLWithPath: masterRow.command).lastPathComponent == "ssh" else {
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("ssh_master_unverified")])
        }
        let command = (try? CoreProcess.run("/bin/ps", ["-ww", "-p", String(master), "-o", "command="], timeout: 5, context: context))?.stdout ?? ""
        let expectedForward = "127.0.0.1:\(transport.settings.cdpLocalPort):127.0.0.1:8080"
        guard command.contains("-L \(expectedForward)") || command.contains("-L\(expectedForward)") else {
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("cdp_forward_unverified")])
        }
        let cdp = try fileDescriptors(arguments: ["-nP", "-iTCP:\(transport.settings.cdpLocalPort)", "-sTCP:LISTEN", "-Fpn"], context: context)
        guard Set(cdp.keys) == [master] else {
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("cdp_listener_not_owned_by_master")])
        }
        let peers = try fileDescriptors(arguments: ["-nP", "-a", "-p", String(master), "-iTCP", "-sTCP:ESTABLISHED", "-Fpn"], context: context)
        let actual = (peers[master] ?? []).compactMap { $0.split(separator: "->").last.map(String.init) }
        let allowed = ["127.0.0.1:\(transport.settings.port)", "[::1]:\(transport.settings.port)"]
        guard actual.count == 1, let peer = actual.first, allowed.contains(peer) else {
            throw CoreError("FX_IDENTITY_UNVERIFIED", ["reason": .string("ssh_peer_unverified")])
        }
        return "\(fxPID)|\(network.map(\.pid).sorted())|\(master)|\(peer)|\(rows[fxPID]?.start ?? "")"
    }

    private static func fileDescriptors(arguments: [String], context: CoreContext?) throws -> [Int: [String]] {
        let result = try CoreProcess.run("/usr/sbin/lsof", arguments, timeout: 8, context: context)
        guard result.status == 0 || !result.stdout.isEmpty else { throw CoreError("FX_IDENTITY_UNVERIFIED") }
        var rows: [Int: [String]] = [:]
        var current: Int?
        for line in result.stdout.split(separator: "\n") {
            if line.hasPrefix("p"), let pid = Int(line.dropFirst()) { current = pid; rows[pid] = [] }
            else if line.hasPrefix("n"), let pid = current { rows[pid, default: []].append(String(line.dropFirst())) }
        }
        return rows
    }

    // MARK: - FX process state

    static func checkFXEntry(request: LaunchRequest, fx: URL, requireRunning: Bool) throws -> [Int: ProcessRow] {
        let rows = try processTable(context: request.context)
        let executable = normalizedExecutable(fx)
        let active = rows.values.filter { URL(fileURLWithPath: normalizedCommand($0.command)).lastPathComponent == "steamac-vm" }
        let foreign = foreignProcesses(rows: rows, executable: executable)
        if !foreign.isEmpty {
            let names = foreign.map { row -> String in
                URL(fileURLWithPath: row.command).pathComponents.first(where: { $0.hasSuffix(".app") }) ?? "unknown FX"
            }
            throw CoreError("FX_INSTANCE_MISMATCH", ["stage": .string("CheckingFXEntry"),
                                                     "selected_fx": .string(fx.path),
                                                     "running_fx": .array(foreign.map { .string($0.command) }),
                                                     "running_apps": .array(Set(names).sorted().map { .string($0) }),
                                                     "reason": .string("different_fx_copy"),
                                                     "action": .string("quit_other_fx_normally_then_retry")])
        }
        if requireRunning {
            guard active.contains(where: { normalizedCommand($0.command) == executable }) else {
                throw CoreError("FX_INSTANCE_MISMATCH", ["stage": .string("CheckingFXEntry"),
                                                         "selected_fx": .string(fx.path),
                                                         "reason": .string("selected_fx_process_not_observed")])
            }
            guard networkReady(context: request.context) else {
                throw CoreError("FX_ENTRY_MISMATCH", ["stage": .string("CheckingFXEntry"),
                                                      "reason": .string("expected_gvproxy_not_verified")])
            }
        }
        return rows
    }

    static func networkReady(context: CoreContext?) -> Bool {
        guard let binary = LaunchResources.gvproxyBinary else { return false }
        let state = LaunchResources.gvproxyState()
        guard state.state == "ready" else { return false }
        guard let rows = try? CoreProcess.run("/bin/ps", ["-axo", "command="], timeout: 8, context: context).stdout else { return false }
        let prefix = binary.path + " -listen-vfkit "
        return rows.split(separator: "\n").contains { $0.hasPrefix(prefix) }
    }

    static func fxState(request: LaunchRequest, fx: URL) throws -> [String: JSONValue] {
        let rows = try checkFXEntry(request: request, fx: fx, requireRunning: false)
        let executable = fx.appendingPathComponent("Contents/MacOS/steamac-vm").path
        let running = rows.values.contains { $0.command == executable }
        return ["fx_host_running": .bool(running),
                "fx_process_count": .number(Double(rows.values.filter { $0.command == executable }.count)),
                "fx_path": .string(fx.path), "fx_version": .string(fxVersion(fx)),
                "transport_verified": .bool(running && networkReady(context: request.context)),
                "guest": .string("unverified"), "ssh_connected": .bool(false),
                "main_menu": .string("unverified"), "eac": .string("unverified"),
                "multiplayer": .string("unverified")]
    }

    // MARK: - Launch arguments

    static func launchArguments(transport: SSHTransport) -> [String] {
        let values = (try? CFPreferencesStore(domain: PerformanceDomain.name).read()) ?? [:]
        let cores = SystemProbe.physicalCores() ?? 8
        let cpus = min(max(values["cpus"]?.integer ?? 8, 1), max(1, cores))
        let memory = values["memMiB"]?.integer ?? 8192
        let mem = (4096...24576).contains(memory) && memory % 256 == 0 ? memory : 8192
        let configuredDriver = values["vulkanDriver"]?.text ?? ""
        let driver = ["kosmickrisp", "moltenvk"].contains(configuredDriver) ? configuredDriver : "kosmickrisp"
        guard let wrapper = LaunchResources.wrapper else { return [] }
        return ["--no-wmtr", "--vulkan-driver", driver, "--gvproxy", wrapper.path,
                "--ssh-port", String(transport.settings.port), "--cpus", String(cpus), "--mem", String(mem),
                "--cmdline", "console=hvc0 loglevel=4 rootwait steamac.gpu_mib=6144", "--perf-stats"]
    }

    static func startFX(request: LaunchRequest, fx: URL) throws {
        let lock = try CoreFileLock.acquire(lockURL)
        defer { lock.release() }
        let current = try fxState(request: request, fx: fx)
        if current["fx_host_running"]?.boolean == true {
            _ = try checkFXEntry(request: request, fx: fx, requireRunning: true)
            throw CoreError("FX_ALREADY_RUNNING")
        }
        let integrity = FXDiscoveryService.integrity(app: fx)
        guard integrity["state"]?.text == "verified" else {
            throw CoreError("FX_PROFILE_MISMATCH", ["state": integrity["state"] ?? .string("unverified")])
        }
        _ = try LaunchResources.verifiedForLaunch()
        let transport = SSHTransport.make(request.configuration)
        let arguments = launchArguments(transport: transport)
        guard !arguments.isEmpty else { throw CoreError("GVPROXY_UNAVAILABLE") }
        request.emit("StartingFX", "running", [:])
        let open = try CoreProcess.run("/usr/bin/open", [fx.path, "--args"] + arguments, timeout: 20, context: request.context)
        guard open.status == 0 else { throw CoreError("FX_START_FAILED", ["exit_code": .number(Double(open.status))]) }
        request.emit("WaitingForFXReady", "running", [:])
        let deadline = CoreClock.monotonic + 30
        while CoreClock.monotonic < deadline {
            try request.context.check()
            Thread.sleep(forTimeInterval: 0.25)
            let state = try fxState(request: request, fx: fx)
            if state["fx_host_running"]?.boolean == true, networkReady(context: request.context) {
                request.emit("VerifyingFXIdentity", "running", [:])
                _ = try checkFXEntry(request: request, fx: fx, requireRunning: true)
                request.emit("VerifyingFXIdentity", "done", [:])
                request.emit("WaitingForFXReady", "done", [:])
                return
            }
        }
        throw CoreError("TIMEOUT", ["stage": .string("StartingFX")])
    }

    // MARK: - Stages

    static func preflight(_ request: LaunchRequest) throws -> [String: JSONValue] {
        let fx = try selectedFX(request)
        _ = try ConfigurationService.read()
        let resources = LaunchResources.report()
        guard resources["archive_files_match"]?.boolean == true else {
            throw CoreError("SOURCE_MISMATCH", resources)
        }
        let integrity = FXDiscoveryService.integrity(app: fx)
        let items = DependencyProbe.items(selectedFX: fx, integrity: integrity)
        let ready = items.filter { $0["state"]?.text != "unverified" }
            .allSatisfy { ["ready", "not_required"].contains($0["state"]?.text ?? "") }
        guard integrity["state"]?.text == "verified" else {
            throw CoreError("FX_PROFILE_MISMATCH", ["state": integrity["state"] ?? .string("unverified")])
        }
        guard ready else {
            let bad = items.filter { !["ready", "not_required", "unverified"].contains($0["state"]?.text ?? "") }
            throw CoreError("ENVIRONMENT_CHECK_FAILED", ["items": .array(bad.map { .object($0) })])
        }
        if !SSHTransport.localHost(SSHTransport.make(request.configuration).settings.host) {
            throw CoreError("LOCAL_FX_REQUIRED")
        }
        return ["host_ready": .bool(true), "items": .array(items.map { .object($0) }),
                "fx_version": .string(fxVersion(fx)), "fx_path": .string(fx.path),
                "resource_scope": .string("app_bundle_resources_only"),
                "guest": .string("unverified"), "main_menu": .string("unverified"),
                "single_player": .string("unverified"), "eac": .string("unverified"),
                "multiplayer": .string("unverified")]
    }

    static func connect(_ request: LaunchRequest, fx: URL, transport: SSHTransport) throws -> (GuestSession, [String: JSONValue], [String: JSONValue]) {
        guard networkReady(context: request.context) else {
            throw CoreError("FX_ENTRY_MISMATCH", ["reason": .string("expected_gvproxy_not_verified")])
        }
        let gvproxy = LaunchResources.gvproxyBinary!
        let session = try GuestService.connect(transport, password: request.password, passphrase: request.passphrase,
                                               context: request.context) {
            try hostIdentity(fx: fx, gvproxy: gvproxy, transport: transport, context: request.context)
        }
        let state = try GuestService.state(transport, context: request.context)
        guard state["boot"]?.text == session.boot else {
            throw CoreError("FX_ENTRY_MISMATCH", ["reason": .string("guest_boot_changed")])
        }
        return (session, state, session.plan)
    }

    static func compatibility(_ state: [String: JSONValue]) throws {
        guard state["vulkan"]?.boolean == true else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("vulkan_cmdline_missing")])
        }
        guard state["tool"]?.text == verifiedTool else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("compat_tool_mismatch")])
        }
        guard state["fex"]?.text == verifiedFEX else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("fex_hash_mismatch")])
        }
        guard state["ntdll"]?.text == verifiedNTDLL else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("ntdll_hash_mismatch")])
        }
        let wine = state["wine_core"]?.object ?? [:]
        for (key, expected) in verifiedWine where wine[key]?.text != expected {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("wine_core_mismatch"), "component": .string(key)])
        }
    }

    static func launchOptionsReady(_ state: [String: JSONValue]) -> Bool {
        let launch = state["launch"]?.text ?? ""
        return requiredLaunchTokens.allSatisfy { launch.contains($0) }
    }

    static func checkProxyPort() -> Bool {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(7890).bigEndian)
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr)
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: 1, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }

    static func ensureIPv4(_ transport: SSHTransport, session: GuestSession, sudoPassword: String?, context: CoreContext) throws -> Bool {
        let plan = try GuestService.inspect(transport, context: context)
        let ipv6 = plan["ipv6"]?.object ?? [:]
        if ["all", "default", "eth0", "lo"].allSatisfy({ ipv6[$0]?.text == "1" }) { return false }
        // Passwordless sudo first; a supplied password is verified once and never echoed.
        let probe = try CoreProcess.run("/usr/bin/ssh", transport.commandArgs(), input: "sudo -n -v\n", timeout: 15, context: context)
        var authorized = probe.status == 0
        if !authorized, let password = sudoPassword, !password.isEmpty, !password.contains("\n") {
            let verify = try CoreProcess.run("/usr/bin/ssh", transport.sudoVerifyArgs(), input: password + "\n", timeout: 20, context: context)
            authorized = verify.status == 0
        }
        guard authorized else { throw CoreError("AUTH_REQUIRED", ["credential_kind": .string("sudo_password")]) }
        let result = try CoreProcess.run("/usr/bin/ssh", transport.sudoCommandArgs(), input: GuestScripts.ipv6(boot: session.boot), timeout: 30, context: context)
        guard result.status == 0, let value = try? GuestService.parse(result.stdout, expected: "COMPATIBILITY_CHECK_FAILED"),
              value["ok"]?.boolean == true else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("ipv6_write_failed")])
        }
        return true
    }
}

extension SSHTransport {
    func commandArgs() -> [String] {
        ["-S", settings.socketPath, "-p", String(settings.port), "-l", settings.username,
         "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", settings.host, "sh", "-s"]
    }
    func sudoVerifyArgs() -> [String] {
        ["-S", settings.socketPath, "-p", String(settings.port), "-l", settings.username,
         "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", settings.host, "sudo", "-S", "-p", "", "-v"]
    }
    func sudoCommandArgs() -> [String] {
        ["-S", settings.socketPath, "-p", String(settings.port), "-l", settings.username,
         "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", settings.host, "sudo", "-n", "sh", "-s"]
    }
}
