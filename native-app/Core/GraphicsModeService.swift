import Darwin
import CoreFoundation
import Foundation

enum GraphicsMode: String, Codable {
    case dx12, dx11
}

enum GraphicsModeService {
    static let profileDomain = "es.fxgam.steamac.hd2fx.graphics"
    static let consentRevision = 1
    private static let verifiedFX = "1.9.15"
    private static let wmtHash = "8aadb3969286411b035278ac748c2ad177d3323267b4cd0e1f323bc7e61fc92b"
    private static var directory: URL { CoreFS.nativeData().appendingPathComponent("graphics-mode", isDirectory: true) }
    private static var receipt: URL { directory.appendingPathComponent("transaction.json") }

    struct Transaction: Codable {
        let fxPath: String
        let disk: String
        let diskIdentity: String
        let machine: String
        let executable: String
        let revision: String
        var stage: Stage
        var shutdownIdentity: String?
    }

    enum Stage: String, Codable { case preparing, armed, restoring }

    static func load() throws -> Transaction? {
        guard FileManager.default.fileExists(atPath: receipt.path) else { return nil }
        guard CoreFS.noSymlink(receipt), let data = try? Data(contentsOf: receipt), data.count < 65_536,
              let state = try? JSONDecoder().decode(Transaction.self, from: data) else {
            throw CoreError("GRAPHICS_RECOVERY_REQUIRED")
        }
        return state
    }

    static func report(fx: URL?) throws -> [String: JSONValue] {
        let state = try load()
        let support: String
        if let fx, (try? capability(fx)) != nil { support = "verified_version" }
        else if let fx, FileManager.default.fileExists(atPath: wmtr(fx).path) { support = "unverified_version" }
        else { support = "unsupported" }
        return ["transaction": .bool(state != nil), "phase": .string(state?.stage.rawValue ?? "stable"),
                "capability": .string(support)]
    }

    static func wmtr(_ fx: URL) -> URL {
        fx.appendingPathComponent("Contents/Frameworks/libwmtr_host.dylib")
    }

    static func capability(_ fx: URL) throws {
        let integrity = FXDiscoveryService.integrity(app: fx)
        guard integrity["publisher_signature"]?.boolean == true,
              LaunchService.fxVersion(fx) == verifiedFX,
              try CoreHash.sha256File(wmtr(fx)) == wmtHash else {
            throw CoreError("GRAPHICS_FX_UNSUPPORTED")
        }
    }

    private static func save(_ state: Transaction) throws {
        try CoreFS.atomicWrite(JSONEncoder().encode(state), to: receipt)
    }

    private static func id(ofDisk path: String) throws -> String {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw CoreError("GRAPHICS_DISK_UNVERIFIED")
        }
        return "\(device):\(inode)"
    }

    private static func observedDisk(_ fx: URL, context: CoreContext) throws -> String {
        let table = try LaunchService.processTable(context: context)
        let executable = LaunchService.normalizedExecutable(fx)
        let pid = try LaunchService.fxSupervisorPID(rows: table, executable: executable)
        let children = table.values.filter { $0.ppid == pid && LaunchService.normalizedCommand($0.command) == executable }
        guard children.count == 1 else { throw CoreError("GRAPHICS_DISK_UNVERIFIED") }
        // The VM holds the raw disk and the read-only layer. Limit discovery to regular disk files
        // opened read/write by that exact child, and exclude the application's own resources.
        let result = try CoreProcess.run("/usr/sbin/lsof", ["-nP", "-p", String(children[0].pid), "-Ffant"], timeout: 10, context: context)
        var access = "", type = ""
        var paths = Set<String>()
        for line in result.stdout.split(separator: "\n") {
            switch line.first {
            case "f": access = ""; type = ""
            case "a": access = String(line.dropFirst())
            case "t": type = String(line.dropFirst())
            case "n":
                let path = String(line.dropFirst())
                if type == "REG", access == "u", !path.hasPrefix(fx.path + "/"),
                   let length = (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? NSNumber,
                   length.int64Value >= 4 * 1_024 * 1_024 * 1_024 {
                    paths.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
                }
            default: break
            }
        }
        guard paths.count == 1, let path = paths.first else { throw CoreError("GRAPHICS_DISK_UNVERIFIED") }
        return path
    }

    private static func profile() throws {
        let key = "profile.553850" as CFString
        let data = Data(#"{"env":"","gfx":"dxmt"}"#.utf8)
        let domain = profileDomain as CFString
        if let previous = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Data,
           previous != data { throw CoreError("GRAPHICS_PROFILE_CONFLICT") }
        CFPreferencesSetValue(key, data as CFData, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else {
            throw CoreError("GRAPHICS_PROFILE_CONFLICT")
        }
    }

    private static func start(_ mode: GraphicsMode, record: Transaction, request: LaunchRequest, fx: URL, transport: SSHTransport) throws {
        guard try id(ofDisk: record.disk) == record.diskIdentity else { throw CoreError("GRAPHICS_DISK_UNVERIFIED") }
        let rows = try LaunchService.checkFXEntry(request: request, fx: fx, requireRunning: false)
        guard !rows.values.contains(where: { LaunchService.normalizedCommand($0.command) == LaunchService.normalizedExecutable(fx) }) else {
            throw CoreError("FX_ALREADY_RUNNING")
        }
        var arguments = LaunchService.launchArguments(transport: transport)
        guard !arguments.isEmpty else { throw CoreError("GVPROXY_UNAVAILABLE") }
        if mode == .dx11 {
            try capability(fx)
            try profile()
            arguments.removeAll { $0 == "--no-wmtr" }
            arguments += ["--no-share", "--no-share-library", "--wmtr-lib", wmtr(fx).path]
        }
        arguments += ["--disk", record.disk, "--disk", fx.appendingPathComponent("Contents/Resources/steamac-layer.img").path + ":ro"]
        let environment = mode == .dx11
            ? ["--env", "STEAMAC_DEFAULTS_DOMAIN=\(profileDomain)", "--env", "WMTR_DRAWABLES=3"] : []
        let opened = try CoreProcess.run("/usr/bin/open", ["-a", fx.path] + environment + ["--args"] + arguments,
                                         timeout: 20, context: request.context)
        guard opened.status == 0 else { throw CoreError("FX_START_FAILED") }
        try SetupVMReboot.wait(context: request.context, seconds: 75) {
            (try? LaunchService.endpointIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!,
                                                 transport: transport, context: request.context)) != nil
        }
    }

    private static func stop(_ record: inout Transaction, fx: URL, request: LaunchRequest) throws {
        let executable = LaunchService.normalizedExecutable(fx)
        let rows = try LaunchService.checkFXEntry(request: request, fx: fx, requireRunning: true)
        let supervisor = try LaunchService.fxSupervisorPID(rows: rows, executable: executable)
        let children = rows.values.filter { $0.ppid == supervisor && LaunchService.normalizedCommand($0.command) == executable }
        guard children.count == 1, let child = children.first else { throw CoreError("FX_IDENTITY_UNVERIFIED") }
        let identity = "\(child.pid):\(child.start)"
        if record.shutdownIdentity != identity {
            // The verified FX release translates one SIGTERM to its ordinary guest power-key
            // shutdown. Recording it before dispatch avoids FX treating a retry as Force Quit.
            record.shutdownIdentity = identity
            try save(record)
            guard kill(pid_t(child.pid), SIGTERM) == 0 else { throw CoreError("GRAPHICS_RESTART_REQUIRED") }
        }
        try SetupVMReboot.wait(context: request.context, seconds: 165) {
            try !LaunchService.processTable(context: request.context).values.contains {
                LaunchService.normalizedCommand($0.command) == executable
            }
        }
        record.shutdownIdentity = nil
        try save(record)
    }

    private static func worker(_ operation: String, boot: String, transport: SSHTransport, context: CoreContext) throws -> [String: JSONValue] {
        guard ["prepare", "restore", "verify", "runtime"].contains(operation), UUID(uuidString: boot) != nil,
              let url = Bundle.main.url(forResource: "graphics-mode-guest", withExtension: "txt"),
              let source = try? String(contentsOf: url, encoding: .utf8), !source.contains("\nHD2FX_GRAPHICS_PROGRAM\n") else {
            throw CoreError("GRAPHICS_WORKER_UNAVAILABLE")
        }
        let command = "python3 - \(operation) \(boot) <<'HD2FX_GRAPHICS_PROGRAM'\n" + source + "\nHD2FX_GRAPHICS_PROGRAM\n"
        let result = try transport.run(command, timeout: 200, context: context)
        let state = try GuestService.parse(result.stdout, expected: "GRAPHICS_TRANSACTION_FAILED")
        if result.status != 0 || state["error"] != nil {
            throw CoreError("GRAPHICS_TRANSACTION_FAILED", ["reason": state["error"] ?? .string("worker_failed")])
        }
        guard state["boot"]?.text == boot else { throw CoreError("TARGET_CHANGED") }
        return state
    }

    static func run(mode: GraphicsMode, launch: Bool, request: LaunchRequest, fx: URL) throws -> [String: JSONValue] {
        if mode == .dx11 { try capability(fx) }
        _ = try LaunchResources.verifiedForLaunch()
        guard let network = LaunchResources.gvproxyBinary else { throw CoreError("GVPROXY_UNAVAILABLE") }
        try CoreFS.ensurePrivateDirectory(directory)
        let lock = try CoreFileLock.acquire(directory.appendingPathComponent("lock"))
        defer { lock.release() }
        let fxLock = try CoreFileLock.acquire(LaunchService.lockURL)
        defer { fxLock.release() }
        var record = try load()
        let revision = try ConfigurationService.read().revision
        let executable = try CoreHash.sha256File(URL(fileURLWithPath: LaunchService.normalizedExecutable(fx)))
        if let record {
            guard record.fxPath == fx.path, record.revision == revision, record.executable == executable,
                  try id(ofDisk: record.disk) == record.diskIdentity else { throw CoreError("TARGET_CHANGED") }
        }
        if mode == .dx12, record == nil { return ["state": .string("restored")] }
        let transport = SSHTransport.make(request.configuration)
        guard SSHTransport.localHost(transport.settings.host) else { throw CoreError("LOCAL_FX_REQUIRED") }

        func stage(_ message: String) {
            request.emit("INFO", message, ["graphics_stage": .string(message)])
        }
        func connect() throws -> (GuestSession, String, GraphicsMode) {
            if let record, try observedDisk(fx, context: request.context) != record.disk {
                throw CoreError("TARGET_CHANGED")
            }
            let endpoint = {
                try LaunchService.endpointIdentity(fx: fx, gvproxy: network, transport: transport, context: request.context)
            }
            transport.setSecret(password: request.password, passphrase: request.passphrase)
            try transport.connectWhileGuestStarts(context: request.context, endpointIdentity: endpoint)
            let session = try GuestService.connect(transport, password: request.password, passphrase: request.passphrase,
                                                   context: request.context, allowDXMT: true) {
                try LaunchService.hostIdentity(fx: fx, gvproxy: network, transport: transport, context: request.context)
            }
            let result = try transport.run("cat /etc/machine-id", timeout: 10, context: request.context)
            let machine = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard result.status == 0, machine.range(of: "^[a-f0-9]{32}$", options: .regularExpression) != nil else {
                throw CoreError("TARGET_CHANGED")
            }
            if let record {
                guard machine == record.machine, try observedDisk(fx, context: request.context) == record.disk else {
                    throw CoreError("TARGET_CHANGED")
                }
            }
            return (session, machine, session.plan["graphics"]?.text == "dxmt" ? .dx11 : .dx12)
        }

        let currentRows = try LaunchService.checkFXEntry(request: request, fx: fx, requireRunning: false)
        if !currentRows.values.contains(where: { LaunchService.normalizedCommand($0.command) == LaunchService.normalizedExecutable(fx) }) {
            guard let record else { throw CoreError("FX_NOT_RUNNING") }
            let target: GraphicsMode = mode == .dx11 && record.stage == .armed ? .dx11 : .dx12
            stage("StartingFX")
            try start(target, record: record, request: request, fx: fx, transport: transport)
        }
        var (session, machine, runningMode) = try connect()
        let initialBoot = session.boot
        if record == nil {
            guard runningMode == .dx12 else { throw CoreError("GRAPHICS_RECOVERY_REQUIRED") }
            let path = try observedDisk(fx, context: request.context)
            record = Transaction(fxPath: fx.path, disk: path, diskIdentity: try id(ofDisk: path),
                                 machine: machine, executable: executable, revision: revision, stage: .preparing)
            try save(record!)
        }
        guard var active = record else { throw CoreError("GRAPHICS_RECOVERY_REQUIRED") }

        if mode == .dx11, runningMode == .dx12 {
            guard active.stage != .restoring else { throw CoreError("GRAPHICS_RECOVERY_REQUIRED") }
            stage("PreparingDXMT")
            let prepared: [String: JSONValue]
            do {
                prepared = try worker("prepare", boot: session.boot, transport: transport, context: request.context)
            } catch {
                if !request.context.isCancelled {
                    stage("RestoringDX12")
                    let rollback = try? worker("restore", boot: session.boot, transport: transport, context: request.context)
                    if rollback?["state"]?.text == "restored" { try? FileManager.default.removeItem(at: receipt) }
                }
                throw error
            }
            guard prepared["machine"]?.text == active.machine, prepared["state"]?.text == "armed" else { throw CoreError("TARGET_CHANGED") }
            active.stage = .armed
            try save(active)
            stage("RestartingFX")
            transport.closeMaster()
            try stop(&active, fx: fx, request: request)
            try start(.dx11, record: active, request: request, fx: fx, transport: transport)
            let previousBoot = session.boot
            (session, machine, runningMode) = try connect()
            guard session.boot != previousBoot, machine == active.machine, runningMode == .dx11 else { throw CoreError("TARGET_CHANGED") }
        }
        if mode == .dx12 {
            stage("RestoringDX12")
            if runningMode == .dx11 {
                active.stage = .restoring
                try save(active)
                let pending = try worker("restore", boot: session.boot, transport: transport, context: request.context)
                guard pending["state"]?.text == "restoring" else { throw CoreError("GRAPHICS_RECOVERY_REQUIRED") }
                transport.closeMaster()
                try stop(&active, fx: fx, request: request)
                try start(.dx12, record: active, request: request, fx: fx, transport: transport)
                let previousBoot = session.boot
                (session, machine, runningMode) = try connect()
                guard session.boot != previousBoot, runningMode == .dx12 else { throw CoreError("TARGET_CHANGED") }
            }
            var restored = try worker("restore", boot: session.boot, transport: transport, context: request.context)
            guard restored["state"]?.text == "restored", restored["machine"]?.text == active.machine else {
                throw CoreError("GRAPHICS_RECOVERY_REQUIRED")
            }
            try FileManager.default.removeItem(at: receipt)
            if initialBoot != session.boot { restored["previous_boot"] = .string(initialBoot) }
            return restored
        }

        stage("VerifyingDXMT")
        var result = try worker("verify", boot: session.boot, transport: transport, context: request.context)
        guard result["machine"]?.text == active.machine else { throw CoreError("TARGET_CHANGED") }
        if initialBoot != session.boot { result["previous_boot"] = .string(initialBoot) }
        if launch {
            stage("StartingSteam")
            do {
                try SetupVMReboot.wait(context: request.context, seconds: 100) {
                    try GuestService.steamReady(GuestService.state(transport, context: request.context))
                }
            } catch let failure as CoreError where failure.code == "VM_RECONNECT_TIMEOUT" {
                throw CoreError("GAME_START_FAILED", ["reason": .string("steam_login_not_observed")])
            }
            _ = try GuestService.verify(transport, session: session, context: request.context, allowDXMT: true) {
                try LaunchService.hostIdentity(fx: fx, gvproxy: network, transport: transport, context: request.context)
            }
            stage("LaunchingGame")
            let dispatch = try GuestService.launchGame(transport, session: session, context: request.context)
            let count = try GuestService.waitForGame(transport, attempts: 180, timeout: 120, context: request.context) {}
            result["game_process_detected"] = .bool(count > 0)
            result["game_launch_command_succeeded"] = dispatch["started"] ?? .bool(false)
            result["game_process_count"] = .number(Double(count))
            let runtime = try? worker("runtime", boot: session.boot, transport: transport, context: request.context)
            try request.context.check()
            result["renderer"] = runtime?["renderer"] ?? .string("unverified")
        }
        return result
    }
}
