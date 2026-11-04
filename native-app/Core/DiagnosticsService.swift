import Foundation

/// Host network metadata and the opt-in reversible wired profile. It never configures FX,
/// FlClash or the Guest; Guest/multiplayer states remain unverified.
enum NetworkProfileService {
    static var path: URL { ConfigurationService.settingsURL.deletingLastPathComponent().appendingPathComponent("network-profile.json") }
    static let defaults: [String: JSONValue] = ["version": .number(1), "check_before_launch": .bool(false),
                                                "restore_wifi": .array([]), "phase": .null]

    static func load() throws -> [String: JSONValue] {
        guard FileManager.default.fileExists(atPath: path.path) else { return defaults }
        guard let data = try? Data(contentsOf: path), data.count <= CoreLimits.maxSmallFile,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoreError("UNSUPPORTED_CONFIGURATION") }
        let value = CoreJSON.value(object).object
        guard value["version"]?.integer == 1, value["check_before_launch"]?.boolean != nil,
              let devices = value["restore_wifi"]?.array else { throw CoreError("UNSUPPORTED_CONFIGURATION") }
        let names = devices.compactMap(\.text)
        guard names.count == devices.count, Set(names).count == names.count,
              names.allSatisfy({ $0.range(of: #"^en[0-9]+$"#, options: .regularExpression) != nil }),
              [nil, "applying", "applied", "restoring", "restored", "rollback_failed"].contains(value["phase"]?.text) else {
            throw CoreError("UNSUPPORTED_CONFIGURATION")
        }
        return value
    }

    static func save(_ value: [String: JSONValue]) throws {
        let data = Data(CoreJSON.pretty(.object(value)).utf8)
        try CoreFS.atomicWrite(data, to: path)
    }

    static func command(_ executable: String, _ arguments: [String], required: Bool = true) throws -> String {
        let result = try CoreProcess.run(executable, arguments, timeout: 6)
        if result.status != 0 {
            if required { throw CoreError("NETWORK_CHECK_FAILED") }
            return ""
        }
        return result.stdout
    }

    static func hardwarePorts() throws -> [String: String] {
        let raw = try command("/usr/sbin/networksetup", ["-listallhardwareports"])
        var ports: [String: String] = [:]
        var pending: String?
        for line in raw.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespaces)
            if text.hasPrefix("Hardware Port:") {
                pending = text.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("Device:"), let name = pending {
                let device = text.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
                ports[device] = name; pending = nil
            }
        }
        guard !ports.isEmpty else { throw CoreError("NETWORK_CHECK_FAILED") }
        return ports
    }

    static func wifiPower(_ device: String) -> Bool? {
        guard let raw = try? command("/usr/sbin/networksetup", ["-getairportpower", device], required: false) else { return nil }
        return raw.lowercased().contains("on") ? true : raw.lowercased().contains("off") ? false : nil
    }

    static func defaultInterface() -> String? {
        guard let raw = try? command("/sbin/route", ["-n", "get", "-inet", "default"], required: false) else { return nil }
        for line in raw.split(separator: "\n") where line.contains("interface:") {
            return line.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return nil
    }

    static func inspect() throws -> [String: JSONValue] {
        let ports = try hardwarePorts()
        let wireless = ports.filter { ["wi-fi", "wifi", "airport"].contains($0.value.lowercased()) }.map(\.key).sorted()
        let interface = defaultInterface()
        let name = interface.flatMap { ports[$0] } ?? ""
        var wired = false
        if let interface, !wireless.contains(interface),
           name.range(of: #"ethernet|\blan\b|以太网"#, options: [.regularExpression, .caseInsensitive]) != nil {
            wired = (try? command("/usr/sbin/ipconfig", ["getifaddr", interface], required: false))?.isEmpty == false
        }
        var wifi: [JSONValue] = []
        for device in wireless {
            wifi.append(.object(["device": .string(device), "on": wifiPower(device).map { .bool($0) } ?? .null]))
        }
        let proxy = LaunchService.checkProxyPort()
        return ["default_interface": interface.map { .string($0) } ?? .null,
                "wired_default": .bool(wired), "wifi": .array(wifi),
                "proxy_available": .bool(proxy),
                "ready": .bool(wired && wireless.allSatisfy { wifiPower($0) == false })]
    }

    static func successConditions() -> [String: JSONValue] {
        var result: [String: JSONValue] = ["tun_route": .null, "system_proxy": .null, "flclash_mode": .null, "allow_lan": .null]
        if let route = try? command("/sbin/route", ["-n", "get", "-inet", "1.1.1.1"], required: false) {
            for line in route.split(separator: "\n") where line.contains("interface:") {
                if let value = line.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) {
                    result["tun_route"] = .bool(value.hasPrefix("utun"))
                }
            }
        }
        if let proxy = try? command("/usr/sbin/scutil", ["--proxy"], required: false) {
            result["system_proxy"] = .bool(proxy.range(of: #"(?m)^\s*(HTTP|HTTPS|SOCKS)Enable\s*:\s*1\s*$"#, options: .regularExpression) != nil)
        }
        let flclash = CoreFS.home().appendingPathComponent("Library/Application Support/com.follow.clash/config.yaml")
        if let text = try? String(contentsOf: flclash, encoding: .utf8), text.count < 1_000_000 {
            if let range = text.range(of: #"(?m)^mode:\s*["']?(global|rule|direct)["']?\s*$"#, options: .regularExpression) {
                result["flclash_mode"] = .string(String(text[range].split(separator: ":").last ?? "").trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'"))))
            }
            if let range = text.range(of: #"(?m)^allow-lan:\s*(true|false)\s*$"#, options: .regularExpression) {
                result["allow_lan"] = .bool(text[range].hasSuffix("true"))
            }
        }
        return result
    }

    static func setWifi(_ device: String, on: Bool) throws {
        _ = try command("/usr/sbin/networksetup", ["-setairportpower", device, on ? "on" : "off"])
        guard wifiPower(device) == on else { throw CoreError("NETWORK_CHECK_FAILED", ["reason": .string("wifi_change_unverified")]) }
    }

    static func apply(confirmed: Bool) throws -> [String: JSONValue] {
        guard confirmed else { throw CoreError("CONFIRMATION_REQUIRED") }
        let before = try inspect()
        guard before["wired_default"]?.boolean == true else { throw CoreError("NETWORK_CHECK_FAILED", ["reason": .string("wired_default_required")]) }
        let devices = (before["wifi"]?.array ?? []).compactMap { row -> String? in
            guard row.object["on"]?.boolean == true else { return nil }
            return row.object["device"]?.text
        }
        var profile = try load()
        guard profile["phase"]?.text != "applying" else { throw CoreError("NETWORK_CHECK_FAILED", ["reason": .string("recovery_required")]) }
        let prior = profile["restore_wifi"]?.array.compactMap(\.text) ?? []
        profile["phase"] = .string("applying")
        profile["restore_wifi"] = .array((prior + devices).uniqued().map { .string($0) })
        try save(profile)
        do {
            for device in devices { try setWifi(device, on: false) }
            let after = try inspect()
            guard after["ready"]?.boolean == true else { throw CoreError("NETWORK_CHECK_FAILED", ["reason": .string("profile_verify_failed")]) }
            profile["phase"] = .string("applied")
            try save(profile)
            return ["result": .object(after), "profile": .object(profile), "changed": .bool(!devices.isEmpty)]
        } catch {
            try? restore(confirmed: true)
            throw error
        }
    }

    static func restore(confirmed: Bool) throws -> [String: JSONValue] {
        guard confirmed else { throw CoreError("CONFIRMATION_REQUIRED") }
        var profile = try load()
        let devices = profile["restore_wifi"]?.array.compactMap(\.text) ?? []
        profile["phase"] = .string("restoring")
        try save(profile)
        var changed: [String] = []
        for device in devices where wifiPower(device) == false {
            try setWifi(device, on: true); changed.append(device)
        }
        profile["phase"] = .string("restored")
        try save(profile)
        return ["result": .object(try inspect()), "profile": .object(profile), "changed": .bool(!changed.isEmpty)]
    }

    static func toggleCheck() throws -> [String: JSONValue] {
        var profile = try load()
        profile["check_before_launch"] = .bool(profile["check_before_launch"]?.boolean != true)
        try save(profile)
        return profile
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>(); return filter { seen.insert($0).inserted }
    }
}

/// Bounded, redacted diagnostics history. Never reads credentials or unrelated user files.
enum DiagnosticsStore {
    static var directory: URL { CoreFS.nativeData().appendingPathComponent("diagnostics", isDirectory: true) }
    static var history: URL { directory.appendingPathComponent("history.jsonl") }

    static func historyRows(limit: Int = 100) -> [[String: JSONValue]] {
        guard let data = try? Data(contentsOf: history), data.count <= 8 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").suffix(limit).compactMap { line in
            guard let row = try? JSONDecoder().decode([String: JSONValue].self, from: Data(line.utf8)) else { return nil }
            return CoreRedaction.container(.object(row)).object
        }
    }

    static func append(_ row: [String: JSONValue]) throws {
        try CoreFS.ensurePrivateDirectory(directory)
        var line = Data(CoreJSON.encode(CoreRedaction.container(.object(row))).utf8)
        line.append(0x0a)
        if !FileManager.default.fileExists(atPath: history.path) {
            try CoreFS.atomicWrite(line, to: history)
            return
        }
        let handle = try FileHandle(forWritingTo: history)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    static func recordLaunchProbe(_ report: [String: JSONValue]) -> [String: JSONValue] {
        let row: [String: JSONValue] = ["id": .string(UUID().uuidString), "kind": .string("launch_probe"),
                                        "time": .string(CoreClock.stamp()), "data": .object(report)]
        try? append(row)
        return row
    }

    static func recordMatch(_ result: String, note: String) throws -> [String: JSONValue] {
        guard ["success", "timeout", "disconnect"].contains(result) else { throw CoreError("INVALID_ARGUMENT") }
        let row: [String: JSONValue] = ["id": .string(UUID().uuidString), "kind": .string("match"),
                                        "time": .string(CoreClock.stamp()), "match_result": .string(result),
                                        "note": .string(CoreRedaction.scrub(note)), "source": .string("user_reported"),
                                        "eac": .string("unverified"), "multiplayer": .string("unverified")]
        try append(row)
        return row
    }

    static func summary(_ rows: [[String: JSONValue]]) -> [String: JSONValue] {
        let matches = rows.filter { $0["kind"]?.text == "match" }
        var counts: [String: Int] = [:]
        for row in matches { counts[row["match_result"]?.text ?? "unknown", default: 0] += 1 }
        return ["total": .number(Double(rows.count)), "matches": .number(Double(matches.count)),
                "success": .number(Double(counts["success"] ?? 0)),
                "timeout": .number(Double(counts["timeout"] ?? 0)),
                "disconnect": .number(Double(counts["disconnect"] ?? 0)),
                "source": .string("user_reported_not_verified")]
    }

    static func exportEnvironment() throws -> [String: JSONValue] {
        try CoreFS.ensurePrivateDirectory(directory)
        let report: [String: JSONValue] = ["time": .string(CoreClock.stamp()),
                                           "scope": .string("host_metadata_only"),
                                           "runtime": .string("swift_native_core"),
                                           "os": SystemProbe.systemInfo()["os_version"] ?? .null,
                                           "arch": .string(SystemProbe.architecture()),
                                           "hardware": .object(SystemProbe.hardware()),
                                           "fx": .string("unverified"), "guest": .string("unverified"),
                                           "eac": .string("unverified"), "multiplayer": .string("unverified")]
        let url = directory.appendingPathComponent("environment-\(UUID().uuidString).json")
        try CoreFS.atomicWrite(Data(CoreJSON.pretty(.object(report)).utf8), to: url)
        return ["export": .string(url.path), "report": .object(report)]
    }

    static func exportNetwork(_ rows: [[String: JSONValue]], windows: [String: JSONValue] = [:]) throws -> [String: JSONValue] {
        try CoreFS.ensurePrivateDirectory(directory)
        let report: [String: JSONValue] = ["time": .string(CoreClock.stamp()), "records": .array(rows.map { .object($0) }),
                                           "summary": .object(summary(rows)), "conditions": .object(windows),
                                           "scope": .string("user_reported_and_local_metadata")]
        let url = directory.appendingPathComponent("network-\(UUID().uuidString).json")
        try CoreFS.atomicWrite(Data(CoreJSON.pretty(.object(report)).utf8), to: url)
        return ["export": .string(url.path)]
    }
}
