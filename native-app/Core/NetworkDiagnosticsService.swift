import Foundation

enum NetworkDiagnosticStatus: String { case inconclusive = "UNVERIFIED", notTested = "NOT_TESTED", running = "RUNNING", pass = "PASS", fail = "FAIL", paused = "PAUSED", timeout = "TIMEOUT", unsupported = "UNSUPPORTED", cancelled = "CANCELLED" }

/// Explicit bounded probes. No configuration mutators, sudo or launch operations.
enum NetworkDiagnosticsService {
    static let targets = ["vm": "identity-bound Guest SSH", "steam": "store.steampowered.com:443 via Host 127.0.0.1:7890",
                          "playfab": "title.playfabapi.com:443 (Guest direct + Guest gateway proxy)",
                          "udp": "stun.cloudflare.com:3478 + stun.l.google.com:19302 (Guest UDP)"]
    static func row(_ name: String, _ status: NetworkDiagnosticStatus, reason: String = "", ms: Double? = nil,
                    details: [JSONValue] = []) -> [String: JSONValue] {
        ["name": .string(name), "target": .string(targets[name] ?? ""), "status": .string(status.rawValue),
         "at": .string(CoreClock.stamp()), "reason": .string(reason), "ms": ms.map(JSONValue.number) ?? .null,
         "details": .array(details), "advice": .string(status == .pass ? "scope_only" : status == .paused ? "connect_or_idle" : "retry_check_route")]
    }
    static func classifyCurl(_ result: CoreProcessResult) -> NetworkDiagnosticStatus {
        if result.timedOut || result.status == 28 { return .timeout }
        if result.status == 127 { return .unsupported }
        return result.status == 0 ? .pass : .fail
    }
    static func curlArgs(host: String, proxy: String?) -> [String] {
        var args = ["--disable", "--silent", "--show-error", "--head", "--output", "/dev/null", "--connect-timeout", "2", "--max-time", "3",
                    "--proto", "=https", "--write-out", "%{time_appconnect}"]
        // Ignore ambient proxy config. Never use --insecure or authentication.
        args += ["--proxy", proxy ?? "", "--noproxy", proxy == nil ? "*" : ""]
        return args + ["https://" + host + "/"]
    }
    static func requestBytes(transaction: [UInt8]) -> [UInt8] { [0, 1, 0, 0, 0x21, 0x12, 0xa4, 0x42] + transaction }
    static func validSTUN(_ data: Data, transaction: [UInt8]) -> Bool {
        let b = Array(data)
        guard transaction.count == 12, b.count >= 20, b[0] == 1, b[1] == 1,
              Array(b[4..<8]) == [0x21, 0x12, 0xa4, 0x42], Array(b[8..<20]) == transaction else { return false }
        let length = Int(b[2]) * 256 + Int(b[3])
        return length % 4 == 0 && length + 20 == b.count
    }
    static func udpScript(host: String, port: Int, transaction: [UInt8]) -> String {
        guard [("stun.cloudflare.com", 3478), ("stun.l.google.com", 19302)].contains(where: { $0.0 == host && $0.1 == port }), transaction.count == 12 else { return "exit 64\n" }
        let octal = requestBytes(transaction: transaction).map { String(format: "\\%03o", $0) }.joined()
        let body = "exec 3<>/dev/udp/" + host + "/" + String(port) + "; printf '%b' '" + octal + "' >&3; dd bs=2048 count=1 <&3 2>/dev/null | base64"
        return "command -v timeout >/dev/null && command -v base64 >/dev/null && command -v dd >/dev/null && [ -x /bin/bash ] || exit 127\ntimeout 2 /bin/bash -c " + shellQuote(body) + "\n"
    }
    static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func guestCurl(host: String, proxy: String?) -> String {
        "command -v curl >/dev/null || exit 127\ncurl " + curlArgs(host: host, proxy: proxy).map(shellQuote).joined(separator: " ") + "\n"
    }
    static func run(bound: SteamOSNetworkService.Bound?, bindingFailure: String?, context: CoreContext,
                    emit: (String, String, [String: JSONValue]) -> Void,
                    hostProbe: (([String], CoreContext) throws -> CoreProcessResult)? = nil,
                    guestProbe: ((String, TimeInterval, CoreContext) throws -> CoreProcessResult)? = nil) throws -> [String: JSONValue] {
        var rows: [[String: JSONValue]] = []
        func publish(_ value: [String: JSONValue]) { emit("INFO", "network_diagnostic", ["kind": .string("network_diagnostic"), "diagnostic": .object(value)]) }
        func add(_ value: [String: JSONValue]) { rows.append(value); publish(value) }
        func guest(_ script: String, _ timeout: TimeInterval = 8) throws -> CoreProcessResult {
            try context.check()
            if let guestProbe { return try guestProbe(script, timeout, context) }
            guard let bound else { throw CoreError("SSH_DISCONNECTED") }
            try bound.verify(context)
            let r = try bound.transport.run(script, timeout: timeout, context: context)
            try bound.verify(context)
            return r
        }
        for name in ["vm", "steam", "playfab", "udp"] { publish(row(name, .notTested)) }
        let start = CoreClock.monotonic
        var idle = false
        do {
            publish(row("vm", .running))
            let r = try guest("command -v pgrep >/dev/null || exit 127\nif pgrep -x helldivers2.exe >/dev/null || pgrep -x reaper >/dev/null; then printf 'busy'; else printf 'idle'; fi\n")
            if r.status == 127 { add(row("vm", .unsupported, reason: "pgrep_unavailable")) } else {
            guard r.status == 0, ["idle", "busy"].contains(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw CoreError("GUEST_INSPECTION_FAILED") }
            idle = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "idle"
            add(row("vm", .pass, ms: (CoreClock.monotonic - start) * 1000))
            }
        } catch {
            if context.isCancelled { throw CoreError("CANCELLED") }
            add(row("vm", (error as? CoreError)?.code == "TIMEOUT" ? .timeout : bindingFailure == nil ? .fail : .paused, reason: bindingFailure ?? (error as? CoreError)?.code ?? "SSH_DISCONNECTED"))
        }
        // Original status_monitor only sends external TLS when game absence is known.
        guard idle else {
            for name in ["steam", "playfab", "udp"] { add(row(name, .paused, reason: "game_running_or_guest_unverified")) }
            return ["items": .array(rows.map(JSONValue.object)), "read_only": .bool(true), "multiplayer": .string("NOT_TESTED")]
        }
        try context.check()
        publish(row("steam", .running))
        if hostProbe == nil && !LaunchService.checkProxyPort() { add(row("steam", .paused, reason: "local_proxy_not_ready")) } else { do {
            let args = curlArgs(host: "store.steampowered.com", proxy: "http://127.0.0.1:7890")
            let r = try hostProbe?(args, context) ?? CoreProcess.run("/usr/bin/curl", args, timeout: 5, context: context)
            let status = classifyCurl(r)
            add(row("steam", status, reason: status == .pass ? "verified_tls_only" : "curl_" + String(r.status), ms: Double(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).map { $0 * 1000 }))
        } catch { try context.check(); add(row("steam", .fail, reason: (error as? CoreError)?.code ?? "probe_failed")) }
        }
        publish(row("playfab", .running))
        var routes: [JSONValue] = []
        var routeStatuses: [NetworkDiagnosticStatus] = []
        for route in ["direct", "proxy"] {
            try context.check()
            do {
                let r = try guest(guestCurl(host: "title.playfabapi.com", proxy: route == "proxy" ? "http://192.168.127.254:7890" : nil))
                let status = classifyCurl(r); routeStatuses.append(status)
                routes.append(.object(["route": .string(route), "status": .string(status.rawValue), "curl_code": .number(Double(r.status)),
                    "ms": Double(r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).map { .number($0 * 1000) } ?? .null]))
            } catch { try context.check(); routeStatuses.append(.fail); routes.append(.object(["route": .string(route), "status": .string("FAIL"), "reason": .string((error as? CoreError)?.code ?? "probe_failed")])) }
        }
        let playfab: NetworkDiagnosticStatus = routeStatuses.contains(.pass) ? .pass : routeStatuses.allSatisfy({ $0 == .timeout }) ? .timeout : routeStatuses.allSatisfy({ $0 == .unsupported }) ? .unsupported : .fail
        add(row("playfab", playfab, reason: "tls_reachability_not_login", details: routes))
        publish(row("udp", .running))
        let counterScript = #"""
awk '/^Udp:/{if(!seen++){for(i=2;i<=NF;i++)h[i]=$i}else{for(i=2;i<=NF;i++)if(h[i]=="InDatagrams" || h[i]=="OutDatagrams")print h[i] "=" $i}}' /proc/net/snmp
if sockets=$(ss -uanp 2>/dev/null); then printf '%s\n' "$sockets" | awk '/helldivers2.exe/{n++;if($5!="*:*" && $5!="0.0.0.0:*" && $5!="[::]:*")c++} END{print "game_sockets=" (n+0);print "connected_sockets=" (c+0)}'; fi
"""#
        func counters() -> [String: Int] {
            guard let result = try? guest(counterScript), result.status == 0 else { return [:] }
            var values: [String: Int] = [:]
            for line in result.stdout.split(separator: "\n") {
                let pair = line.split(separator: "=")
                if pair.count == 2, let value = Int(pair[1]), value >= 0 { values[String(pair[0])] = value }
            }
            return values
        }
        let countersBefore = counters()
        var samples: [JSONValue] = []; var statuses: [NetworkDiagnosticStatus] = []; var latencies: [String: [Double]] = [:]
        for _ in 0..<2 {
            for (host, port) in [("stun.cloudflare.com", 3478), ("stun.l.google.com", 19302)] {
                try context.check()
                let nonce = (0..<12).map { _ in UInt8.random(in: 0...255) }
                let before = CoreClock.monotonic
                do {
                    let r = try guest(udpScript(host: host, port: port, transaction: nonce), 5)
                    let data = Data(base64Encoded: r.stdout.filter { !$0.isWhitespace }) ?? Data()
                    let status: NetworkDiagnosticStatus = r.status == 127 ? .unsupported : (r.status == 124 || r.timedOut) ? .timeout : r.status == 0 && validSTUN(data, transaction: nonce) ? .pass : .fail
                    statuses.append(status)
                    let ms = (CoreClock.monotonic - before) * 1000
                    if status == .pass { latencies[host, default: []].append(ms) }
                    samples.append(.object(["target": .string(host + ":" + String(port)), "status": .string(status.rawValue), "ms": status == .pass ? .number(ms) : .null]))
                } catch { try context.check(); statuses.append(.fail); samples.append(.object(["target": .string(host), "status": .string("FAIL"), "reason": .string((error as? CoreError)?.code ?? "probe_failed")])) }
            }
        }
        let status: NetworkDiagnosticStatus = statuses.filter({ $0 == .pass }).count >= 2 ? .pass : statuses.contains(.pass) ? .inconclusive : statuses.allSatisfy({ $0 == .timeout }) ? .timeout : statuses.allSatisfy({ $0 == .unsupported }) ? .unsupported : .fail
        let rtts = latencies.values.flatMap { $0 }
        var udp = row("udp", status, reason: "stun_only_not_nat_or_multiplayer", ms: rtts.isEmpty ? nil : rtts.reduce(0,+) / Double(rtts.count), details: samples)
        let changes = latencies.values.filter { $0.count == 2 }.map { abs($0[1] - $0[0]) }
        udp["successes"] = .number(Double(statuses.filter { $0 == .pass }.count))
        udp["samples"] = .number(Double(statuses.count))
        udp["jitter_ms"] = changes.isEmpty ? .null : .number(changes.reduce(0,+) / Double(changes.count))
        // Preserve the original sampling window, but cancellation remains responsive.
        for _ in 0..<30 { try context.check(); Thread.sleep(forTimeInterval: 0.1) }
        let countersAfter = counters()
        for key in ["InDatagrams", "OutDatagrams"] {
            if let before = countersBefore[key], let after = countersAfter[key], after >= before { udp[key + "_delta"] = .number(Double(after - before)) }
        }
        for key in ["game_sockets", "connected_sockets"] {
            if let value = [countersBefore[key], countersAfter[key]].compactMap({ $0 }).max() { udp[key] = .number(Double(value)) }
        }
        udp["latency_scope"] = .string("includes_ssh_command_and_identity_checks")
        add(udp)
        return ["items": .array(rows.map(JSONValue.object)), "read_only": .bool(true), "multiplayer": .string("NOT_TESTED"), "nat": .string("unknown")]
    }
}
