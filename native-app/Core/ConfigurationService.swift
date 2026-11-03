import Foundation

/// Launcher settings (the legacy `settings.json` contract), read/written natively.
/// Every write is revision-guarded, backed up and atomically replaced.
enum ConfigurationService {
    static let sshDefaults: [String: JSONValue] = [
        "host": .string("127.0.0.1"), "port": .number(2222), "username": .string("steamos"),
        "auth": .string("password"), "identity_file": .string(""), "cdp_local_port": .number(18094),
        "remember_password": .bool(false)]
    static let appearanceDefaults: [String: JSONValue] = [
        "emblem": .string("current"), "intro_animation": .bool(true),
        "layout": .string("immersive"), "language": .null]

    static var settingsURL: URL { CoreFS.appSupport().appendingPathComponent("settings.json") }
    static var lockURL: URL { CoreFS.appSupport().appendingPathComponent(".native-config.lock") }

    static func defaults() -> [String: JSONValue] {
        ["version": .number(1), "ssh": .object(sshDefaults), "appearance": .object(appearanceDefaults),
         "ssh_configured": .bool(false)]
    }

    static func rawRevision(_ data: Data) -> String { CoreHash.sha256(data) }

    static func readRaw() throws -> (data: Data, revision: String) {
        let url = settingsURL
        if FileManager.default.isSymbolicLink(atPath: url.path) { throw CoreError("UNSAFE_PATH") }
        guard FileManager.default.fileExists(atPath: url.path) else {
            let data = Data()
            return (data, rawRevision(data))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        if let size = (attributes[.size] as? NSNumber)?.intValue, size > CoreLimits.maxSmallFile { throw CoreError("OUTPUT_LIMIT") }
        let data = try Data(contentsOf: url)
        return (data, rawRevision(data))
    }

    static func parse(_ data: Data) throws -> [String: JSONValue] {
        if data.isEmpty { return defaults() }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw CoreError("INVALID_ARGUMENT") }
        return try validate(CoreJSON.value(object).object)
    }

    static func validatedSSH(_ raw: [String: JSONValue]) throws -> [String: JSONValue] {
        var ssh = sshDefaults
        for (key, value) in raw where ssh[key] != nil { ssh[key] = value }
        let host = ssh["host"]?.text ?? ""
        guard !host.isEmpty, host.count <= 255,
              host.range(of: #"^[A-Za-z0-9][A-Za-z0-9_.:%-]*$"#, options: .regularExpression) != nil else { throw CoreError("INVALID_ARGUMENT") }
        let username = ssh["username"]?.text ?? ""
        guard username.range(of: #"^[A-Za-z_][A-Za-z0-9_.-]*\$?$"#, options: .regularExpression) != nil else { throw CoreError("INVALID_ARGUMENT") }
        for key in ["port", "cdp_local_port"] {
            guard let value = ssh[key]?.integer, (1...65535).contains(value) else { throw CoreError("INVALID_ARGUMENT") }
        }
        guard ssh["port"]?.integer != ssh["cdp_local_port"]?.integer else { throw CoreError("INVALID_ARGUMENT") }
        guard ["password", "key"].contains(ssh["auth"]?.text ?? "") else { throw CoreError("INVALID_ARGUMENT") }
        guard ssh["remember_password"]?.boolean != nil else { throw CoreError("INVALID_ARGUMENT") }
        guard let identity = ssh["identity_file"]?.text, !identity.contains("\n") else { throw CoreError("INVALID_ARGUMENT") }
        return ssh
    }

    static func validate(_ data: [String: JSONValue]) throws -> [String: JSONValue] {
        guard data["version"]?.integer == 1 else { throw CoreError("INVALID_ARGUMENT") }
        guard let rawSSH = data["ssh"]?.object else { throw CoreError("INVALID_ARGUMENT") }
        let ssh = try validatedSSH(rawSSH)
        let appearance = data["appearance"]?.object ?? [:]
        let emblem = appearance["emblem"]?.text ?? "current"
        guard ["current", "1", "2", "3", "4"].contains(emblem) else { throw CoreError("INVALID_ARGUMENT") }
        let intro = appearance["intro_animation"]?.boolean ?? true
        let layout = appearance["layout"]?.text ?? "immersive"
        guard ["immersive", "compact"].contains(layout) else { throw CoreError("INVALID_ARGUMENT") }
        let language = appearance["language"]?.text
        if let language, !NativeLanguageCodes.all.contains(language) { throw CoreError("INVALID_ARGUMENT") }
        if data["ssh_configured"] != nil, data["ssh_configured"]?.boolean == nil { throw CoreError("INVALID_ARGUMENT") }
        return ["version": .number(1), "ssh": .object(ssh),
                "ssh_configured": .bool(data["ssh_configured"]?.boolean ?? false),
                "appearance": .object(["emblem": .string(emblem), "intro_animation": .bool(intro),
                                       "layout": .string(layout), "language": language.map { .string($0) } ?? .null])]
    }

    static func read() throws -> (configuration: [String: JSONValue], revision: String) {
        let (data, revision) = try readRaw()
        return (try parse(data), revision)
    }

    static func resultRead() throws -> [String: JSONValue] {
        let (configuration, revision) = try read()
        return ["configuration": .object(configuration), "revision": .string(revision),
                "target": .string(settingsURL.path),
                "credential_policy": .string("session_memory_only_keychain_ignored")]
    }

    static func save(patch rawPatch: JSONValue, expectedRevision: String) throws -> [String: JSONValue] {
        guard case .object(let patch) = rawPatch else { throw CoreError("INVALID_ARGUMENT") }
        let allowed: Set<String> = ["ssh", "ssh_configured", "appearance", "version"]
        guard Set(patch.keys).isSubset(of: allowed) else { throw CoreError("INVALID_ARGUMENT") }
        if CoreRedaction.containsSecret(CoreJSON.encode(rawPatch)) { throw CoreError("SENSITIVE_CONFIGURATION") }
        var (configuration, revision) = try read()
        guard revision == expectedRevision else { throw CoreError("CONFIG_CHANGED") }
        for (key, value) in patch {
            if case .object(let nested) = value, case .object(let current)? = configuration[key] {
                var merged = current
                for (nestedKey, nestedValue) in nested {
                    guard current[nestedKey] != nil else { throw CoreError("INVALID_ARGUMENT") }
                    merged[nestedKey] = nestedValue
                }
                configuration[key] = .object(merged)
            } else {
                configuration[key] = value
            }
        }
        let validated = try validate(configuration)
        let directory = settingsURL.deletingLastPathComponent()
        try CoreFS.ensurePrivateDirectory(directory)
        let lock = try CoreFileLock.acquire(lockURL)
        defer { lock.release() }
        var (liveConfiguration, liveRevision) = try read()
        guard liveRevision == expectedRevision else { throw CoreError("CONFIG_CHANGED") }
        _ = liveConfiguration
        let backup = try CoreFS.backupFile(settingsURL, directory: directory, label: "settings.native-backup")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(JSONValue.object(validated))
        data.append(0x0a)
        try CoreFS.atomicWrite(data, to: settingsURL)
        let (_, newRevision) = try readRaw()
        return ["saved": .bool(true), "target": .string(settingsURL.path),
                "backup": backup.map { .string($0.path) } ?? .null,
                "revision": .string(newRevision)]
    }

    /// Explicit operator backup of the launcher settings, independent of writes.
    static func snapshot(reason: String) throws -> [String: JSONValue] {
        let (configuration, revision) = try read()
        let directory = CoreFS.nativeData().appendingPathComponent("settings-backups", isDirectory: true)
        try CoreFS.ensurePrivateDirectory(directory)
        let body: [String: JSONValue] = ["version": .number(1),
                                         "created": .string(CoreClock.stamp()),
                                         "reason": .string(reason),
                                         "revision": .string(revision),
                                         "configuration": .object(configuration),
                                         "fx_identity": .object(FXDefaultsSummary.current())]
        let envelope = ["body": JSONValue.object(body), "sha256": .string(CoreHash.sha256(Data(CoreJSON.encode(.object(body)).utf8)))]
        let data = Data(CoreJSON.pretty(.object(envelope)).utf8)
        let path = directory.appendingPathComponent("settings-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString.prefix(8)).json")
        try CoreFS.atomicWrite(data, to: path)
        return ["path": .string(path.path), "created": .string(body["created"]?.text ?? ""),
                "revision": .string(revision), "sha256": .string(CoreHash.sha256(data))]
    }

    static func backups() -> [String: JSONValue] {
        let directory = CoreFS.nativeData().appendingPathComponent("settings-backups", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let rows: [JSONValue] = names.filter { $0.hasSuffix(".json") }.sorted().suffix(20).reversed().map { name in
            let url = directory.appendingPathComponent(name)
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return .object(["name": .string(name), "path": .string(url.path),
                            "size": .number(Double((attributes?[.size] as? NSNumber)?.intValue ?? 0)),
                            "created": .string((attributes?[.creationDate] as? Date).map { CoreClock.stamp($0) } ?? "unknown")])
        }
        return ["backups": .array(rows), "directory": .string(directory.path)]
    }

    static func restore(path rawPath: String, confirmed: Bool) throws -> [String: JSONValue] {
        guard confirmed else { throw CoreError("CONFIRMATION_REQUIRED") }
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL
        let directory = CoreFS.nativeData().appendingPathComponent("settings-backups", isDirectory: true)
        guard url.path.hasPrefix(directory.path + "/"), url.pathExtension == "json" else { throw CoreError("UNSAFE_PATH") }
        guard let data = try? Data(contentsOf: url), data.count <= CoreLimits.maxSmallFile,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = envelope["body"] as? [String: Any],
              let digest = envelope["sha256"] as? String else { throw CoreError("PERF_BACKUP") }
        let bodyValue = CoreJSON.value(body)
        guard digest == CoreHash.sha256(Data(CoreJSON.encode(bodyValue).utf8)) else { throw CoreError("PERF_BACKUP") }
        guard let configuration = bodyValue.object["configuration"] else { throw CoreError("PERF_BACKUP") }
        let validated = try validate(configuration.object)
        let targetDirectory = settingsURL.deletingLastPathComponent()
        try CoreFS.ensurePrivateDirectory(targetDirectory)
        let lock = try CoreFileLock.acquire(lockURL)
        defer { lock.release() }
        let backup = try CoreFS.backupFile(settingsURL, directory: targetDirectory, label: "settings.pre-restore")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var output = try encoder.encode(JSONValue.object(validated))
        output.append(0x0a)
        try CoreFS.atomicWrite(output, to: settingsURL)
        let (reread, revision) = try read()
        guard CoreJSON.encode(.object(reread)) == CoreJSON.encode(.object(validated)) else { throw CoreError("CONFIG_CHANGED") }
        return ["restored": .bool(true), "target": .string(settingsURL.path),
                "backup": backup.map { .string($0.path) } ?? .null,
                "revision": .string(revision)]
    }
}

enum FXDefaultsSummary {
    static func current() -> [String: JSONValue] {
        ["recorded": .bool(false), "note": .string("fx identity is recorded by the performance backup")]
    }
}

enum NativeLanguageCodes {
    static let all = ["zh-CN", "en", "ja", "ko", "ru", "es", "de", "fr", "pt-BR", "zh-TW"]
    static var isolatedTest: Bool {
        ProcessInfo.processInfo.arguments.contains("--native-core-checks")
    }
}
