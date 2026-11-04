import Foundation
import CoreFoundation

/// Parameter-scoped FX preference persistence (cpus, memory, Vulkan driver, Metal HUD).
/// CFPreferences is authoritative; writes require a stopped, publisher-verified FX.
enum PerformanceDomain {
    static let name = "es.fxgam.steamac"
    static let keys = ["cpus", "memMiB", "vulkanDriver", "metalHUD", "superResolution"]
    static let pinned194 = "0db013e9766b77e1c40f588c5f02ce1bab5937ec88cc17d6a8ade6c53e00b0cb"
}

protocol PreferencesStore {
    func read() throws -> [String: JSONValue]
    func write(_ values: [String: JSONValue?]) throws
    var label: String { get }
}

struct CFPreferencesStore: PreferencesStore {
    let domain: String
    var label: String { domain }

    private var appID: CFString { domain as CFString }

    func read() throws -> [String: JSONValue] {
        guard CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw CoreError("PERF_STORE") }
        let dictionary = CFPreferencesCopyMultiple(nil, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as NSDictionary
        var result: [String: JSONValue] = [:]
        for (key, value) in dictionary {
            guard let name = key as? String else { continue }
            result[name] = CoreJSON.value(value)
        }
        if result.isEmpty { throw CoreError("PERF_FORMAT") }
        return result
    }

    func write(_ values: [String: JSONValue?]) throws {
        var set: [String: Any] = [:]
        var remove: [String] = []
        for (key, value) in values {
            switch value {
            case .none, .some(.null): remove.append(key)
            case .some(.string(let text)): set[key] = text
            case .some(.number(let number)): set[key] = Int(number)
            case .some(.bool(let flag)): set[key] = flag
            case .some(let other): throw CoreError("PERF_FORMAT", ["value": other])
            }
        }
        CFPreferencesSetMultiple(set as CFDictionary, remove as CFArray, appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        guard CFPreferencesSynchronize(appID, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) else { throw CoreError("PERF_STORE") }
    }
}

struct MemoryPreferencesStore: PreferencesStore {
    final class Box {
        var values: [String: JSONValue]
        init(values: [String: JSONValue]) { self.values = values }
    }
    let box: Box
    var label: String { "memory" }
    init(_ values: [String: JSONValue]) { box = Box(values: values) }
    func read() throws -> [String: JSONValue] { box.values }
    func write(_ values: [String: JSONValue?]) throws {
        for (key, value) in values {
            if case .none = value { box.values.removeValue(forKey: key) }
            else if case .some(.null) = value { box.values.removeValue(forKey: key) }
            else if let value { box.values[key] = value }
        }
    }
}

struct PerformanceRules: Sendable {
    let version: String
    let cpuMin: Int, cpuMax: Int
    let memoryMin: Int, memoryMax: Int, memoryStep: Int
    let drivers: [String]
    let writable: Set<String>
    var json: [String: JSONValue] {
        ["version": .string(version), "cpu_min": .number(Double(cpuMin)), "cpu_max": .number(Double(cpuMax)),
         "memory_min": .number(Double(memoryMin)), "memory_max": .number(Double(memoryMax)),
         "memory_step": .number(Double(memoryStep)), "drivers": .array(drivers.map { .string($0) }),
         "writable": .array(writable.sorted().map { .string($0) }),
         "super_resolution_reason": .string("device_support_not_probed"),
         "command_line_overrides": .bool(true)]
    }
}

enum PerformanceError {
    static func normalize(_ error: Error) -> CoreError {
        if let core = error as? CoreError { return core }
        return CoreError("PERF_STORE")
    }
}

enum PerformanceConfigurationService {
    static var directory: URL { CoreFS.nativeData().appendingPathComponent("performance-v2", isDirectory: true) }

    static func digest(_ values: [String: JSONValue]) -> String {
        CoreHash.sha256(Data(CoreJSON.encode(.object(values)).utf8))
    }

    static func selected(_ values: [String: JSONValue]) -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        for key in PerformanceDomain.keys { result[key] = values[key] ?? .null }
        return result
    }

    static func capabilities(app: URL) throws -> PerformanceRules {
        guard let identity = FXDiscoveryService.identity(of: app.path), identity.valid else { throw CoreError("PERF_VERSION") }
        let integrity = FXDiscoveryService.integrity(app: app)
        let trusted = integrity["state"]?.text == "verified"
        let pinned = try? CoreHash.sha256File(identity.executable) == PerformanceDomain.pinned194
        guard trusted || pinned == true else { throw CoreError("PERF_VERSION") }
        let memoryMiB = (SystemProbe.memoryBytes() ?? 0) / 1_048_576
        let cores = SystemProbe.physicalCores() ?? 0
        guard memoryMiB > 0, cores > 0 else { throw CoreError("PERF_VERSION") }
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        var drivers: [String] = []
        let frameworks = app.appendingPathComponent("Contents/Frameworks")
        if osMajor >= 15, FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("libMoltenVK.dylib").path) { drivers.append("moltenvk") }
        if osMajor >= 26, FileManager.default.fileExists(atPath: frameworks.appendingPathComponent("libvulkan_kosmickrisp.dylib").path) { drivers.append("kosmickrisp") }
        let maximum = min(16384, max(0, memoryMiB - max(3072, memoryMiB / 4) - 6144) / 256 * 256)
        return PerformanceRules(version: identity.version,
                                cpuMin: 1, cpuMax: min(255, cores),
                                memoryMin: 4096, memoryMax: maximum, memoryStep: 256,
                                drivers: drivers, writable: ["cpus", "memMiB", "vulkanDriver", "metalHUD"])
    }

    static func validate(_ values: [String: JSONValue], rules: PerformanceRules, restore: Bool) throws {
        guard Set(values.keys) == Set(PerformanceDomain.keys) else { throw CoreError("PERF_PARAMETER") }
        for (key, value) in values {
            if restore, case .null = value { continue }
            switch key {
            case "cpus":
                guard let number = value.integer, (rules.cpuMin...rules.cpuMax).contains(number) else { throw CoreError("PERF_RANGE") }
            case "memMiB":
                guard let number = value.integer, (rules.memoryMin...rules.memoryMax).contains(number),
                      number % rules.memoryStep == 0 else { throw CoreError("PERF_RANGE") }
            case "vulkanDriver":
                guard let text = value.text, rules.drivers.contains(text) else { throw CoreError("PERF_PARAMETER") }
            case "metalHUD", "superResolution":
                guard value.boolean != nil else { throw CoreError("PERF_PARAMETER") }
            default:
                throw CoreError("PERF_PARAMETER")
            }
        }
    }

    static func stopped() throws {
        let names = try CoreProcess.processNames()
        guard !names.isEmpty else { throw CoreError("PERF_STATE_UNKNOWN") }
        let blocked: Set<String> = ["steamac-vm", "gvproxy", "gvproxy-eim", "krun"]
        if names.contains(where: { blocked.contains(URL(fileURLWithPath: $0).lastPathComponent) }) { throw CoreError("PERF_RUNNING") }
    }

    static func prepareDirectory() throws {
        try CoreFS.ensurePrivateDirectory(directory)
    }

    static func withLock<T>(_ body: () throws -> T) throws -> T {
        try prepareDirectory()
        let lock = try CoreFileLock.acquire(directory.appendingPathComponent("lock"))
        defer { lock.release() }
        return try body()
    }

    static func save(_ body: [String: JSONValue], to path: URL) throws {
        let data = Data(CoreJSON.encode(.object(body)).utf8)
        try CoreFS.atomicWrite(data, to: path)
    }

    static func envelope(_ body: [String: JSONValue]) -> [String: JSONValue] {
        ["body": .object(body), "sha256": .string(CoreHash.sha256(Data(CoreJSON.encode(.object(body)).utf8)))]
    }

    static func receipt() throws -> [String: JSONValue] {
        let path = directory.appendingPathComponent("last.json")
        if FileManager.default.isSymbolicLink(atPath: path.path) { throw CoreError("PERF_BACKUP") }
        guard let data = try? Data(contentsOf: path), data.count <= CoreLimits.maxSmallFile,
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let body = envelope["body"] as? [String: Any], let digest = envelope["sha256"] as? String else { throw CoreError("PERF_BACKUP") }
        let value = CoreJSON.value(body)
        guard digest == CoreHash.sha256(Data(CoreJSON.encode(value).utf8)) else { throw CoreError("PERF_BACKUP") }
        guard let version = value.object["version"]?.text, !version.isEmpty,
              value.object["domain"]?.text == PerformanceDomain.name else { throw CoreError("PERF_BACKUP") }
        return value.object
    }

    static func snapshot(store: PreferencesStore, rules: PerformanceRules) throws -> [String: JSONValue] {
        let data = try store.read()
        let current = selected(data)
        guard !current.values.contains(where: { if case .null = $0 { return true }; return false }) else { throw CoreError("PERF_FORMAT") }
        try validate(current, rules: rules, restore: false)
        var backup: [String: JSONValue]?
        if let receipt = try? receipt() { backup = receipt }
        let canRestore = backup?["status"]?.text == "saved" && backup?["after_revision"]?.text == digest(data)
        return ["current": .object(current), "revision": .string(digest(data)),
                "capabilities": .object(rules.json), "effective": .string("unverified"),
                "last_applied": backup?["after"] ?? .null,
                "backup": backup?["before"] ?? .null,
                "can_restore": .bool(canRestore == true),
                "store": .string(store.label),
                "scope": .string("parameter_scoped_fx_preferences")]
    }

    static func preview(values rawValues: [String: JSONValue]?, revision: String, restore: Bool,
                        store: PreferencesStore, rules: PerformanceRules,
                        probe: () throws -> Void = stopped) throws -> [String: JSONValue] {
        try probe()
        let current = try snapshot(store: store, rules: rules)
        guard current["revision"]?.text == revision else { throw CoreError("PERF_CONFLICT") }
        var values = rawValues ?? [:]
        if restore {
            let receipt = try receipt()
            guard current["can_restore"]?.boolean == true else { throw CoreError("PERF_CONFLICT") }
            values = receipt["before"]?.object ?? [:]
        }
        try validate(values, rules: rules, restore: restore)
        for key in PerformanceDomain.keys {
            if !rules.writable.contains(key), values[key] != current["current"]?.object[key], !restore {
                throw CoreError("PERF_PARAMETER")
            }
        }
        var changes: [String: JSONValue] = [:]
        for key in PerformanceDomain.keys where values[key] != current["current"]?.object[key] {
            changes[key] = .object(["before": current["current"]?.object[key] ?? .null, "after": values[key] ?? .null])
        }
        if changes.isEmpty { throw CoreError("PERF_UNCHANGED") }
        let plan: [String: JSONValue] = ["before": current["current"] ?? .object([:]),
                                         "after": .object(values), "revision": .string(revision),
                                         "restore": .bool(restore), "version": .string(rules.version)]
        let token = CoreHash.sha256(Data(CoreJSON.encode(.object(plan)).utf8))
        return ["plan": .object(plan), "token": .string(token), "changes": .object(changes)]
    }

    static func commit(values: [String: JSONValue]?, revision: String, token: String, restore: Bool,
                       store: PreferencesStore, rules: PerformanceRules,
                       probe: () throws -> Void = stopped,
                       emit: (String) -> Void) throws -> [String: JSONValue] {
        try withLock {
            let preview = try preview(values: values, revision: revision, restore: restore, store: store, rules: rules, probe: probe)
            guard preview["token"]?.text == token else { throw CoreError("PERF_CONFLICT") }
            let before = try store.read()
            let after = preview["plan"]?.object["after"]?.object ?? [:]
            emit("backing_up")
            let body: [String: JSONValue] = ["domain": .string(PerformanceDomain.name),
                                             "version": .string(rules.version),
                                             "created": .number(Date().timeIntervalSince1970),
                                             "source": .string("native_performance_v3"),
                                             "validation": .string("saved_not_effective"),
                                             "before": .object(selected(before)), "after": .object(after),
                                             "status": .string("prepared"),
                                             "before_revision": .string(digest(before))]
            let backup = directory.appendingPathComponent("backup-\(Int(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.prefix(6)).json")
            try save(envelope(body), to: backup)
            guard (try? Data(contentsOf: backup)).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) != nil else {
                throw CoreError("PERF_BACKUP")
            }
            guard digest(try store.read()) == revision else { throw CoreError("PERF_CONFLICT") }
            emit(restore ? "restoring" : "applying")
            do {
                var writeValues: [String: JSONValue?] = [:]
                for key in PerformanceDomain.keys { writeValues[key] = after[key] ?? .null }
                try store.write(writeValues)
                var expected = before
                for key in PerformanceDomain.keys {
                    if case .some(.null) = writeValues[key] { expected.removeValue(forKey: key) }
                    else { expected[key] = after[key] }
                }
                guard digest(try store.read()) == digest(expected) else { throw CoreError("PERF_VERIFY") }
            } catch {
                let observed = try store.read()
                var expected = before
                for key in PerformanceDomain.keys {
                    if case .some(.null) = after[key] { expected.removeValue(forKey: key) } else { expected[key] = after[key] }
                }
                if digest(observed) == digest(expected) {
                    try probe()
                    var owned: [String: JSONValue?] = [:]
                    for key in PerformanceDomain.keys { owned[key] = before[key] ?? .null }
                    try store.write(owned)
                    guard digest(try store.read()) == digest(before) else { throw CoreError("PERF_ROLLBACK") }
                } else if digest(observed) != digest(before) {
                    throw CoreError("PERF_CONFLICT")
                }
                throw error
            }
            var updated = body
            updated["status"] = .string(restore ? "restored" : "saved")
            updated["after_revision"] = .string(digest(try store.read()))
            try save(envelope(updated), to: backup)
            try save(envelope(updated), to: directory.appendingPathComponent("last.json"))
            var result = try snapshot(store: store, rules: rules)
            result["status"] = updated["status"]
            result["restart_required"] = .bool(true)
            result["effective"] = .string("unverified")
            emit("waiting_restart")
            return result
        }
    }
}
