import Foundation

/// Single native entry point replacing the Python bridge. Same request/reply contract so the
/// existing supervised UI keeps its bindings while no interpreter or script directory is used.
actor NativeCoreService {
    static let protocolVersion = 1

    private var inFlight = false
    private var logRing: [[String: JSONValue]] = []

    struct Operation { let method: String; let scope: String; let confirmation: Bool; let external: Bool }

    static let operations: [Operation] = [
        Operation(method: "read_configuration", scope: "settings", confirmation: false, external: false),
        Operation(method: "save_configuration", scope: "settings", confirmation: true, external: false),
        Operation(method: "backup_configuration", scope: "settings", confirmation: false, external: false),
        Operation(method: "list_configuration_backups", scope: "settings", confirmation: false, external: false),
        Operation(method: "restore_configuration", scope: "settings", confirmation: true, external: false),
        Operation(method: "inspect_legacy_runtime", scope: "fx", confirmation: false, external: false),
        Operation(method: "inspect_network", scope: "environment", confirmation: false, external: false),
        Operation(method: "test_network", scope: "environment", confirmation: false, external: false),
        Operation(method: "test_ssh", scope: "environment", confirmation: true, external: true),
        Operation(method: "test_guest_sudo", scope: "settings", confirmation: true, external: true),
        Operation(method: "connect_fx", scope: "environment", confirmation: true, external: true),
        Operation(method: "inspect_guest_environment", scope: "environment", confirmation: true, external: true),
        Operation(method: "check_fx_state", scope: "fx", confirmation: false, external: false),
        Operation(method: "start_fx", scope: "fx", confirmation: true, external: true),
        Operation(method: "start_steam", scope: "fx", confirmation: true, external: true),
        Operation(method: "inspect_guest", scope: "environment", confirmation: true, external: true),
        Operation(method: "launch_game", scope: "dashboard", confirmation: true, external: true),
        Operation(method: "preflight_launch", scope: "dashboard", confirmation: false, external: false),
        Operation(method: "observe_launch", scope: "dashboard", confirmation: true, external: true),
        Operation(method: "apply_performance", scope: "settings", confirmation: true, external: true),
        Operation(method: "read_performance", scope: "performance", confirmation: false, external: false),
        Operation(method: "performance_read", scope: "performance", confirmation: false, external: false),
        Operation(method: "performance_preview", scope: "performance", confirmation: false, external: false),
        Operation(method: "performance_apply", scope: "performance", confirmation: true, external: true),
        Operation(method: "performance_restore_preview", scope: "performance", confirmation: false, external: false),
        Operation(method: "performance_restore", scope: "performance", confirmation: true, external: true),
        Operation(method: "apply_network_profile", scope: "environment", confirmation: true, external: true),
        Operation(method: "restore_network_profile", scope: "environment", confirmation: true, external: true),
        Operation(method: "toggle_network_check", scope: "environment", confirmation: true, external: false),
        Operation(method: "save_network_snapshot", scope: "environment", confirmation: true, external: true),
        Operation(method: "record_match", scope: "environment", confirmation: true, external: false),
        Operation(method: "read_network_history", scope: "environment", confirmation: false, external: false),
        Operation(method: "export_network_report", scope: "logs", confirmation: true, external: false),
        Operation(method: "export_environment_report", scope: "logs", confirmation: true, external: false),
        Operation(method: "get_legacy_catalog", scope: "settings", confirmation: false, external: false),
    ]

    static let readMethods: Set<String> = ["handshake", "get_launcher_version", "get_system_info",
                                           "get_environment_status", "get_dependencies", "list_fx_versions",
                                           "get_logs", "inspect_launch_target"]

    private static let allowedParams: Set<String> = [
        "fx_path", "confirmed", "runtime_root", "password", "passphrase", "sudo_password",
        "credential_revision", "approved_changes", "configuration", "expected_revision",
        "channel", "match_result", "note", "values", "preview_token", "backup_path",
        "selected_paths"]

    func request(_ method: String, timeout: TimeInterval = 5,
                 params: [String: JSONValue] = [:],
                 onEvent: (@Sendable ([String: JSONValue]) -> Void)? = nil) async throws -> BridgeReply {
        guard !inFlight else { throw ErrorState("BUSY", method: method) }
        inFlight = true
        defer { inFlight = false }
        let context = CoreContext(timeout: timeout)
        return try await withTaskCancellationHandler {
            if Task.isCancelled { throw ErrorState("CANCELLED", method: method) }
            let reply = try await Task.detached(priority: .userInitiated) {
                try Self.perform(method, params: params, context: context, onEvent: onEvent)
            }.value
            await self.appendReplyLog(method, reply: reply)
            return reply
        } onCancel: {
            context.cancel()
        }
    }

    private func appendReplyLog(_ method: String, reply: BridgeReply) {
        logRing.append(["at": .string(reply.observedAt), "source": .string("native_core"),
                        "level": .string("INFO"), "message": .string(method + ": OK")])
        if logRing.count > 200 { logRing.removeFirst(logRing.count - 200) }
    }

    // MARK: - Dispatch

    nonisolated static func perform(_ method: String, params: [String: JSONValue], context: CoreContext,
                                    onEvent: (@Sendable ([String: JSONValue]) -> Void)?) throws -> BridgeReply {
        let requestID = UUID().uuidString
        let secrets = ["password", "passphrase", "sudo_password"].compactMap { params[$0]?.text }
        func emit(_ level: String, _ message: String, _ extra: [String: JSONValue] = [:]) {
            var row: [String: JSONValue] = ["at": .string(CoreClock.stamp()), "source": .string("native_core"),
                                            "level": .string(level), "message": .string(CoreRedaction.scrub(message, secrets: secrets))]
            for (key, value) in extra { row[key] = value }
            onEvent?(row)
        }
        do {
            try context.check()
            guard Set(params.keys).isSubset(of: allowedParams) else { throw CoreError("INVALID_ARGUMENT") }
            if let revision = params["credential_revision"]?.text, !secrets.isEmpty {
                let (_, current) = try ConfigurationService.read()
                guard current == revision else { throw CoreError("CREDENTIAL_SCOPE_CHANGED") }
            }
            if let operation = operations.first(where: { $0.method == method }), operation.confirmation,
               params["confirmed"]?.boolean != true {
                throw CoreError("CONFIRMATION_REQUIRED")
            }
            let result = try dispatch(method, params: params, context: context, emit: emit)
            return BridgeReply(result: result, observedAt: CoreClock.stamp(), requestID: requestID)
        } catch let error as CoreError {
            throw ErrorState(error.code, method: method,
                             details: CoreRedaction.container(.object(error.details)).object)
        } catch {
            emit("ERROR", method + " failed")
            throw ErrorState("CORE_UNAVAILABLE", method: method)
        }
    }

    nonisolated static func dispatch(_ method: String, params: [String: JSONValue], context: CoreContext,
                                     emit: @escaping (String, String, [String: JSONValue]) -> Void) throws -> [String: JSONValue] {
        switch method {
        case "handshake":
            return ["protocol_min": .number(1), "protocol_max": .number(1),
                    "capabilities": .array((Array(readMethods).sorted() + operations.map(\.method)).map { .string($0) }),
                    "read_only": .bool(false), "permission_model": .string("explicit_actions"),
                    "read_only_default": .bool(true), "runtime": .string("swift_native_core"),
                    "python_required": .bool(false)]
        case "get_launcher_version":
            return SystemProbe.launcherVersion()
        case "get_system_info":
            return SystemProbe.systemInfo()
        case "get_environment_status":
            return SystemProbe.environmentStatus()
        case "get_dependencies":
            return DependencyProbe.summary(selectedFX: selectedFXURL(params))
        case "list_fx_versions":
            return FXDiscoveryService.scan(selectedPaths: params["selected_paths"]?.array.compactMap(\.text) ?? [],
                                           runtimeRoot: params["runtime_root"]?.text)
        case "get_logs":
            return ["entries": .array([]), "source": .string("native_core_session"),
                    "game_logs": .string("NOT_CAPTURED"), "next_cursor": .null]
        case "inspect_launch_target":
            guard let fxPath = params["fx_path"]?.text else { return FXDiscoveryService.launchTarget(fxPath: nil) }
            return FXDiscoveryService.launchTarget(fxPath: fxPath)
        case "read_configuration":
            return try ConfigurationService.resultRead()
        case "save_configuration":
            guard let revision = params["expected_revision"]?.text, let configuration = params["configuration"] else {
                throw CoreError("INVALID_ARGUMENT")
            }
            return try ConfigurationService.save(patch: configuration, expectedRevision: revision)
        case "backup_configuration":
            return try ConfigurationService.snapshot(reason: params["note"]?.text ?? "manual")
        case "list_configuration_backups":
            return ConfigurationService.backups()
        case "restore_configuration":
            guard let path = params["backup_path"]?.text else { throw CoreError("INVALID_ARGUMENT") }
            return try ConfigurationService.restore(path: path, confirmed: params["confirmed"]?.boolean == true)
        case "read_performance":
            return readPerformance()
        case "performance_read":
            let (store, rules, fx) = try performanceContext(params)
            var result = try PerformanceConfigurationService.snapshot(store: store, rules: rules)
            result["hardware"] = .object(SystemProbe.hardware())
            result["fx_path"] = .string(fx.path)
            return result
        case "performance_preview", "performance_restore_preview":
            let (store, rules, _) = try performanceContext(params)
            guard let revision = params["expected_revision"]?.text else { throw CoreError("INVALID_ARGUMENT") }
            return try PerformanceConfigurationService.preview(values: params["values"]?.object,
                                                               revision: revision,
                                                               restore: method == "performance_restore_preview",
                                                               store: store, rules: rules)
        case "performance_apply", "performance_restore":
            let (store, rules, _) = try performanceContext(params)
            guard let revision = params["expected_revision"]?.text, let token = params["preview_token"]?.text else {
                throw CoreError("INVALID_ARGUMENT")
            }
            return try PerformanceConfigurationService.commit(values: params["values"]?.object, revision: revision,
                                                              token: token,
                                                              restore: method == "performance_restore",
                                                              store: store, rules: rules) { status in
                emit("INFO", "Performance configuration", ["performance_status": .string(status)])
            }
        case "apply_performance":
            // Legacy broad profile apply stays unavailable: no validated portable ranges.
            throw CoreError("PROFILE_NOT_APPLICABLE", ["reason": .string("no_validated_ranges_or_scoped_backend")])
        case "inspect_network":
            return ["host": .object(try NetworkProfileService.inspect()),
                    "conditions": .object(NetworkProfileService.successConditions()),
                    "guest": .string("unverified"), "multiplayer": .string("unverified")]
        case "test_network":
            let proxy = LaunchService.checkProxyPort()
            let host = try NetworkProfileService.inspect()
            return ["proxy_port": .bool(proxy), "wifi": host["wifi"] ?? .array([]),
                    "routes": .object(NetworkProfileService.successConditions()),
                    "scope": .string("host_local_only"), "guest": .string("unverified"),
                    "eac": .string("unverified"), "multiplayer": .string("unverified")]
        case "apply_network_profile":
            return try NetworkProfileService.apply(confirmed: params["confirmed"]?.boolean == true)
        case "restore_network_profile":
            return try NetworkProfileService.restore(confirmed: params["confirmed"]?.boolean == true)
        case "toggle_network_check":
            return try NetworkProfileService.toggleCheck()
        case "test_ssh":
            return try testSSH(params, context: context, emit: emit)
        case "test_guest_sudo":
            return try testSudo(params, context: context, emit: emit)
        case "check_fx_state":
            let request = try launchRequest(params, context: context, emit: emit, confirmed: false)
            let fx = try LaunchService.selectedFX(request)
            return try LaunchService.fxState(request: request, fx: fx)
        case "start_fx":
            let request = try launchRequest(params, context: context, emit: emit, confirmed: true)
            let fx = try LaunchService.selectedFX(request)
            let state = try LaunchService.fxState(request: request, fx: fx)
            if state["fx_host_running"]?.boolean == true {
                _ = try LaunchService.checkFXEntry(request: request, fx: fx, requireRunning: true)
                var value = state; value["already_running"] = .bool(true); return value
            }
            try LaunchService.startFX(request: request, fx: fx)
            let current = try LaunchService.fxState(request: request, fx: fx)
            var value = current; value["already_running"] = .bool(false); return value
        case "connect_fx", "inspect_guest_environment", "inspect_guest", "start_steam",
             "save_network_snapshot", "observe_launch", "launch_game":
            return try runGUI(method, params: params, context: context, emit: emit)
        case "preflight_launch":
            let request = try launchRequest(params, context: context, emit: emit, confirmed: false)
            return try LaunchService.preflight(request)
        case "inspect_legacy_runtime":
            let request = try launchRequest(params, context: context, emit: emit, confirmed: false)
            let fx = try LaunchService.selectedFX(request)
            let integrity = FXDiscoveryService.integrity(app: fx)
            let items = DependencyProbe.items(selectedFX: fx, integrity: integrity)
            return ["items": .array(items.map { .object($0) }),
                    "resources": .object(LaunchResources.report()),
                    "runtime_path": .string(fx.path),
                    "gvproxy_path": .string(LaunchResources.gvproxyBinary?.path ?? ""),
                    "fx_version": .string(LaunchService.fxVersion(fx)),
                    "integrity": .object(integrity),
                    "guest": .string("unverified"), "eac": .string("unverified"),
                    "multiplayer": .string("unverified")]
        case "read_network_history":
            let rows = DiagnosticsStore.historyRows()
            return ["records": .array(rows.map { .object($0) }), "summary": .object(DiagnosticsStore.summary(rows))]
        case "record_match":
            guard let result = params["match_result"]?.text else { throw CoreError("INVALID_ARGUMENT") }
            return ["record": .object(try DiagnosticsStore.recordMatch(result, note: params["note"]?.text ?? "")),
                    "source": .string("user_reported")]
        case "export_network_report":
            let rows = DiagnosticsStore.historyRows()
            return try DiagnosticsStore.exportNetwork(rows, windows: NetworkProfileService.successConditions())
        case "export_environment_report":
            return try DiagnosticsStore.exportEnvironment()
        case "get_legacy_catalog":
            return catalog()
        case "check_updates":
            throw CoreError("NOT_IMPLEMENTED", ["reason": .string("sparkle_owns_launcher_updates")])
        default:
            throw CoreError("NOT_IMPLEMENTED")
        }
    }

    // MARK: - Helpers

    static func selectedFXURL(_ params: [String: JSONValue]) -> URL? {
        if let path = params["fx_path"]?.text, !path.isEmpty { return URL(fileURLWithPath: path) }
        if let stored = UserDefaults.standard.string(forKey: "NativeDefaultFXPath"), !stored.isEmpty {
            return URL(fileURLWithPath: stored)
        }
        return nil
    }

    static func performanceContext(_ params: [String: JSONValue]) throws -> (PreferencesStore, PerformanceRules, URL) {
        guard let fx = selectedFXURL(params), let identity = FXDiscoveryService.identity(of: fx.path), identity.valid else {
            throw CoreError("FX_UNAVAILABLE")
        }
        let rules = try PerformanceConfigurationService.capabilities(app: URL(fileURLWithPath: identity.path))
        return (CFPreferencesStore(domain: PerformanceDomain.name), rules, URL(fileURLWithPath: identity.path))
    }

    static func readPerformance() -> [String: JSONValue] {
        let hardware = SystemProbe.hardware()
        var current: [String: JSONValue] = [:]
        var issues: [JSONValue] = []
        let store = CFPreferencesStore(domain: PerformanceDomain.name)
        let values = (try? store.read()) ?? [:]
        for key in PerformanceDomain.keys {
            if let value = values[key] { current[key] = value } else { current[key] = .null; issues.append(.string(key)) }
        }
        return ["hardware": .object(hardware), "current": .object(current),
                "reference": .object(PerformanceDomain.keys.enumerated().reduce(into: [String: JSONValue]()) { result, pair in
                    let reference: [String: JSONValue] = ["cpus": .number(8), "memMiB": .number(8192),
                                                          "vulkanDriver": .string("kosmickrisp"),
                                                          "metalHUD": .bool(false), "superResolution": .bool(false)]
                    result[pair.element] = reference[pair.element]
                }),
                "source": .string("es.fxgam.steamac"),
                "preference_domain": .string(PerformanceDomain.name),
                "read_errors": .array(issues), "effective": .string("unverified"),
                "can_apply": .bool(false), "can_restore": .bool(false),
                "reason": .string("legacy_broad_profile_apply_disabled_use_scoped_performance_panel")]
    }

    static func launchRequest(_ params: [String: JSONValue], context: CoreContext,
                              emit: @escaping (String, String, [String: JSONValue]) -> Void,
                              confirmed: Bool) throws -> LaunchRequest {
        guard !confirmed || params["confirmed"]?.boolean == true else { throw CoreError("CONFIRMATION_REQUIRED") }
        let (configuration, _) = try ConfigurationService.read()
        guard let fxPath = params["fx_path"]?.text ?? UserDefaults.standard.string(forKey: "NativeDefaultFXPath") else {
            throw CoreError("FX_UNAVAILABLE")
        }
        return LaunchRequest(configuration: configuration, fxPath: fxPath,
                             password: params["password"]?.text, passphrase: params["passphrase"]?.text,
                             sudoPassword: params["sudo_password"]?.text,
                             approvedChanges: params["approved_changes"]?.array ?? [],
                             context: context, emit: emit)
    }

    static func testSSH(_ params: [String: JSONValue], context: CoreContext,
                        emit: (String, String, [String: JSONValue]) -> Void) throws -> [String: JSONValue] {
        let (configuration, _) = try ConfigurationService.read()
        var settings = configuration["ssh"]?.object ?? [:]
        settings["cdp_local_port"] = .number(19000 + Double(Int.random(in: 0..<900)))
        var transport = SSHTransport.make(["ssh": .object(settings)])
        transport = SSHTransport(settings: .init(host: transport.settings.host, port: transport.settings.port,
                                                 username: transport.settings.username, auth: transport.settings.auth,
                                                 identityFile: transport.settings.identityFile,
                                                 cdpLocalPort: transport.settings.cdpLocalPort,
                                                 rememberPassword: transport.settings.rememberPassword,
                                                 socketPath: "/tmp/hd2fx-test-\(getuid())-\(UUID().uuidString.prefix(8)).sock"))
        defer { transport.closeMaster() }
        try transport.connectOnce(context: context)
        let result = try transport.run("printf 'HD2FX_SSH_OK\\n'\n", timeout: 15, context: context)
        guard result.status == 0, result.stdout.contains("HD2FX_SSH_OK") else { throw CoreError("SSH_CONNECTION_FAILED") }
        emit("INFO", "SSH authentication succeeded", ["kind": .string("credential_status"),
                                                      "credential_kind": .string("ssh"), "status": .string("authenticated")])
        return ["ssh": .string("authenticated"), "guest_python": .string("not_required"),
                "game": .string("unverified"), "eac": .string("unverified"), "multiplayer": .string("unverified")]
    }

    static func testSudo(_ params: [String: JSONValue], context: CoreContext,
                         emit: @escaping (String, String, [String: JSONValue]) -> Void) throws -> [String: JSONValue] {
        let request = try launchRequest(params, context: context, emit: emit, confirmed: true)
        let fx = try LaunchService.selectedFX(request)
        let transport = SSHTransport.make(request.configuration)
        guard LaunchService.networkReady(context: context) else { throw CoreError("FX_NOT_RUNNING") }
        _ = try LaunchService.checkFXEntry(request: request, fx: fx, requireRunning: true)
        let session = try GuestService.connect(transport, password: request.password, passphrase: request.passphrase,
                                               context: context) {
            try LaunchService.hostIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!,
                                           transport: transport, context: context)
        }
        let probe = try transport.run("sudo -n -v >/dev/null 2>&1 && printf 'OK\\n' || printf 'FAILED\\n'\n",
                                      timeout: 15, context: context)
        if probe.stdout.contains("OK") {
            return ["sudo": .string("available_without_password_prompt"), "password_verified": .bool(false),
                    "configuration_changed": .bool(false), "guest_boot": .string(session.boot)]
        }
        guard let password = request.sudoPassword, !password.isEmpty, !password.contains("\n") else {
            throw CoreError("AUTH_REQUIRED", ["credential_kind": .string("sudo_password")])
        }
        let verify = try CoreProcess.run("/usr/bin/ssh", transport.sudoVerifyArgs(), input: password + "\n", timeout: 20, context: context)
        guard verify.status == 0 else { throw CoreError("SUDO_AUTH_FAILED") }
        emit("INFO", "Guest sudo authenticated", ["kind": .string("credential_status"),
                                                  "credential_kind": .string("sudo"), "status": .string("authenticated")])
        return ["sudo": .string("authenticated"), "password_verified": .bool(true),
                "configuration_changed": .bool(false), "guest_boot": .string(session.boot)]
    }

    static func runGUI(_ method: String, params: [String: JSONValue], context: CoreContext,
                       emit: @escaping (String, String, [String: JSONValue]) -> Void) throws -> [String: JSONValue] {
        var stage = "CheckingFXEntry"
        func stageEmit(_ name: String, _ status: String) {
            stage = name
            emit(status == "failed" ? "ERROR" : "INFO", name, ["stage": .string(name), "status": .string(status)])
        }
        do {
            let request = try launchRequest(params, context: context, emit: emit, confirmed: method != "observe_launch")
            let fx = try LaunchService.selectedFX(request)
            let transport = SSHTransport.make(request.configuration)
            guard SSHTransport.localHost(transport.settings.host) else { throw CoreError("LOCAL_FX_REQUIRED") }
            stageEmit("CheckingFXEntry", "running")
            var host = try LaunchService.fxState(request: request, fx: fx)
            if host["fx_host_running"]?.boolean != true {
                if method == "start_fx" {
                    try LaunchService.startFX(request: request, fx: fx)
                    host = try LaunchService.fxState(request: request, fx: fx)
                } else {
                    throw CoreError("FX_NOT_RUNNING")
                }
            }
            _ = try LaunchService.checkFXEntry(request: request, fx: fx, requireRunning: true)
            if method == "check_fx_state" { return host }
            stageEmit("WaitingForGuest", "running")
            let (session, state, plan) = try LaunchService.connect(request, fx: fx, transport: transport)
            emit("INFO", "Guest identity verified", ["kind": .string("credential_status"),
                                                     "credential_kind": .string("ssh"), "status": .string("authenticated")])
            let connected: [String: JSONValue] = {
                var value = host
                value["ssh_connected"] = .bool(true)
                value["guest_ready"] = .bool(true)
                value["guest_service"] = plan["service"] ?? .string("unknown")
                value["guest_boot"] = .string(session.boot)
                return value
            }()
            switch method {
            case "connect_fx":
                return connected
            case "start_steam":
                stageEmit("StartingSteam", "running")
                _ = try GuestService.verify(transport, session: session, context: context) {
                    try LaunchService.hostIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!, transport: transport, context: context)
                }
                let result = try GuestService.steam(transport, session: session, context: context)
                let final = try GuestService.inspect(transport, context: context)
                guard final["service"]?.text == "running" else { throw CoreError("STEAM_START_FAILED") }
                var value = connected
                value["steam_running"] = .bool(true)
                value["steam_started"] = .bool(result["started"]?.boolean == true)
                return value
            case "launch_game":
                return try launchGame(request, fx: fx, transport: transport, session: session, state: state,
                                      connected: connected, context: context, emit: emit, stage: &stage)
            case "observe_launch":
                let current = try GuestService.state(transport, context: context)
                let count = current["game_count"]?.integer ?? 0
                return ["game_process_detected": .bool(count > 0),
                        "game_process_count": .number(Double(count)),
                        "steam_process_count": .number(Double(current["steam_count"]?.integer ?? 0)),
                        "main_menu": .string("unverified"), "single_player": .string("unverified"),
                        "eac": .string("unverified"), "multiplayer": .string("unverified")]
            default:
                break
            }
            stageEmit("ReadingGuest", "running")
            let environment = try guestEnvironment(transport, state: state, context: context)
            _ = try GuestService.verify(transport, session: session, context: context) {
                try LaunchService.hostIdentity(fx: fx, gvproxy: LaunchResources.gvproxyBinary!, transport: transport, context: context)
            }
            var value = environment
            for (key, item) in connected { value[key] = item }
            if method == "inspect_guest" {
                return CoreRedaction.container(.object(value)).object
            }
            if method == "save_network_snapshot" {
                try DiagnosticsStore.append(["id": .string(UUID().uuidString), "kind": .string("snapshot"),
                                             "time": .string(CoreClock.stamp()), "data": .object(value)])
                return ["saved": .string(DiagnosticsStore.history.path), "snapshot": .object(value)]
            }
            return value
        } catch let error as CoreError {
            var details = error.details
            details["stage"] = details["stage"] ?? .string(stage)
            emit("ERROR", error.code, ["stage": .string(stage), "status": .string("failed")])
            throw CoreError(error.code, details)
        } catch {
            emit("ERROR", "launch step failed", ["stage": .string(stage), "status": .string("failed")])
            throw CoreError("GUEST_INSPECTION_FAILED", ["stage": .string(stage)])
        }
    }

    static func guestEnvironment(_ transport: SSHTransport, state: [String: JSONValue],
                                 context: CoreContext) throws -> [String: JSONValue] {
        let steam = try transport.run(#"""
S="$HOME/.local/share/Steam"
J="$S/compatibilitytools.d/proton-je-11.0-20261014-3"
os=$(uname -s) || os=unknown
arch=$(uname -m) || arch=unknown
sf=false; [ -d "$S" ] && sf=true
gm=false; [ -f "$S/steamapps/appmanifest_553850.acf" ] && gm=true
gd=false; [ -d "$S/steamapps/common/Helldivers 2" ] && gd=true
ge=false; [ -f "$S/steamapps/common/Helldivers 2/bin/helldivers2.exe" ] && ge=true
pf=false; [ -f "$J/proton" ] && pf=true
ff=false; [ -f "$S/steamapps/common/FEX-Emu/usr/bin/FEX" ] && ff=true
printf '{"guest_os":"%s","guest_arch":"%s","components":{"steam_files":%s,"game_manifest":%s,"game_directory":%s,"game_executable":%s,"proton_files":%s,"fex_files":%s}}\n' "$os" "$arch" "$sf" "$gm" "$gd" "$ge" "$pf" "$ff"
"""#, timeout: 20, context: context)
        guard steam.status == 0, let value = try? GuestService.parse(steam.stdout, expected: "GUEST_INSPECTION_FAILED") else {
            throw CoreError("GUEST_INSPECTION_FAILED")
        }
        var result = value
        result["steam_process_count"] = .number(Double(state["steam_count"]?.integer ?? 0))
        result["game_process_count"] = .number(Double(state["game_count"]?.integer ?? 0))
        result["steam_logged_on"] = state["steam_logged_on"] ?? .string("unverified")
        result["scope"] = .string("read_only_file_presence_and_processes")
        result["eac"] = .string("unverified")
        result["multiplayer"] = .string("unverified")
        result["main_menu"] = .string("unverified")
        return result
    }

    static func launchGame(_ request: LaunchRequest, fx: URL, transport: SSHTransport, session: GuestSession,
                           state: [String: JSONValue], connected: [String: JSONValue], context: CoreContext,
                           emit: (String, String, [String: JSONValue]) -> Void, stage: inout String) throws -> [String: JSONValue] {
        func advance(_ name: String, _ status: String) {
            stage = name
            emit(status == "failed" ? "ERROR" : "INFO", name, ["stage": .string(name), "status": .string(status)])
        }
        advance("CheckingCompatibility", "running")
        if let count = state["game_count"]?.integer, count > 0 {
            var value = connected
            value["game_process_detected"] = .bool(true)
            value["game_process_count"] = .number(Double(count))
            value["main_menu"] = .string("unverified")
            value["single_player"] = .string("unverified")
            value["eac"] = .string("unverified")
            value["multiplayer"] = .string("unverified")
            return value
        }
        try LaunchService.compatibility(state)
        guard LaunchService.checkProxyPort() else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("host_proxy_7890_unavailable")])
        }
        guard LaunchService.launchOptionsReady(state) else {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("steam_launch_options_action_required")])
        }
        if let apps = state["apps"]?.text, !apps.isEmpty, !apps.split(separator: " ").allSatisfy({ $0 == "553850" }) {
            throw CoreError("COMPATIBILITY_CHECK_FAILED", ["reason": .string("other_steam_game_running")])
        }
        _ = try LaunchService.ensureIPv4(transport, session: session, sudoPassword: request.sudoPassword, context: context)
        advance("CheckingCompatibility", "done")
        advance("StartingSteam", "running")
        let steamResult = try GuestService.steam(transport, session: session, context: context)
        if steamResult["started"]?.boolean == true { emit("INFO", "Steam started once; not stopped by this app", [:]) }
        advance("StartingSteam", "done")
        advance("LaunchingGame", "running")
        let before = try GuestService.state(transport, context: context)
        guard (before["game_count"]?.integer ?? 0) == 0 else {
            throw CoreError("GAME_START_FAILED", ["reason": .string("game_appeared_during_preparation")])
        }
        let launch = try GuestService.launchGame(transport, session: session, context: context)
        _ = launch
        let count = try GuestService.waitForGame(transport, attempts: 90, context: context)
        var value = connected
        value["game_process_detected"] = .bool(true)
        value["game_process_count"] = .number(Double(count))
        value["main_menu"] = .string("unverified")
        value["single_player"] = .string("unverified")
        value["multiplayer"] = .string("not_requested")
        value["eac"] = .string("unverified")
        advance("GameProcessDetected", "done")
        return value
    }

    static func catalog() -> [String: JSONValue] {
        ["languages": .array(NativeLanguageCodes.all.map { .object(["code": .string($0), "name": .string($0)]) }),
         "operations": .array(operations.map { operation in
             .object(["method": .string(operation.method), "scope": .string(operation.scope),
                      "confirmation": .bool(operation.confirmation), "external_effects": .bool(operation.external)])
         }),
         "help": .object([:]), "help_scope": .string("native_localization_catalogs"),
         "automatic_install": .bool(false), "runtime": .string("swift_native_core")]
    }
}

