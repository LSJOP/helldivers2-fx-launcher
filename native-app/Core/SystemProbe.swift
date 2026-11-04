import Foundation

/// Host-only facts. Nothing here starts, stops or mutates FX, the Guest, Steam or the game.
enum SystemProbe {
    static func launcherVersion() -> [String: JSONValue] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return ["version": .string(version), "build": .string(build),
                "source": .string("swift_native_core"), "ui_version": .string("Native"),
                "terminal_ui": .string("none"), "python_required": .bool(false)]
    }

    static func systemInfo() -> [String: JSONValue] {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        let kernel = unameString()
        return ["os": .string("macOS"), "os_release": .string(kernel ?? "unknown"),
                "os_version": .string(osVersion), "arch": .string(architecture()),
                "native_runtime": .string("Swift Native Core"),
                "python_required": .bool(false), "python": .string("not_required")]
    }

    static func architecture() -> String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static func unameString() -> String? {
        var info = utsname()
        guard uname(&info) == 0 else { return nil }
        return withUnsafePointer(to: &info.release) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }

    static func environmentStatus() -> [String: JSONValue] {
        let names = ["FX launcher", "gvproxy", "SSH connection", "Guest", "Steam", "FEX", "Proton-JE", "EAC", "Multiplayer"]
        return ["status": .string("unverified"), "scope": .string("host_metadata_only"),
                "checks": .array(names.map { .object(["name": .string($0), "state": .string("unverified")]) })]
    }

    static func memoryBytes() -> Int? {
        sysctlInteger("hw.memsize")
    }

    static func physicalCores() -> Int? {
        sysctlInteger("hw.physicalcpu")
    }

    static func cpuBrand() -> String? {
        sysctlString("machdep.cpu.brand_string")
    }

    static func sysctlString(_ name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func sysctlInteger(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0, value > 0 else { return nil }
        return Int(value)
    }

    static func chipName() -> String? {
        guard let raw = cpuBrand() else { return nil }
        let normalized = raw.split(separator: " ").joined(separator: " ")
        let pattern = #"^Apple M[1-9][0-9]*(?: Pro| Max| Ultra)?$"#
        return normalized.range(of: pattern, options: .regularExpression) != nil ? normalized : nil
    }

    static func gpuCores(chip: String) -> Int? {
        guard let result = try? CoreProcess.run("/usr/sbin/system_profiler", ["-json", "SPDisplaysDataType"], timeout: 15),
              result.status == 0,
              let data = result.stdout.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = root["SPDisplaysDataType"] as? [[String: Any]] else { return nil }
        let matching = rows.filter { row in
            let model = (row["sppci_model"] as? String) ?? (row["_name"] as? String) ?? ""
            return model == chip && (row["sppci_bus"] as? String) == "spdisplays_builtin"
        }
        guard matching.count == 1, let cores = matching[0]["sppci_cores"] as? Int, cores > 0 else { return nil }
        return cores
    }

    static func hardware() -> [String: JSONValue] {
        let chip = chipName()
        var result: [String: JSONValue] = ["chip": chip.map { .string($0) } ?? .null,
                                           "memory_bytes": .null, "gpu_cores": .null,
                                           "cpu_cores": (physicalCores()).map { .number(Double($0)) } ?? .null,
                                           "os_version": .string(systemInfo()["os_version"]?.text ?? "unknown")]
        if chip != nil, let memory = memoryBytes() { result["memory_bytes"] = .number(Double(memory)) }
        if let chip, let cores = gpuCores(chip: chip) { result["gpu_cores"] = .number(Double(cores)) }
        return result
    }

    static func hostHasFXProcesses(executable: URL) throws -> (running: Bool, foreign: Bool) {
        let names = try CoreProcess.processNames()
        let target = executable.path
        let all = names.filter { URL(fileURLWithPath: $0).lastPathComponent == "steamac-vm" }
        return (all.contains(target), all.contains { $0 != target })
    }
}

/// Bundled + selected-FX prerequisites. Guest components stay explicitly unverified.
enum DependencyProbe {
    static func items(selectedFX: URL?, integrity: [String: JSONValue]? = nil) -> [[String: JSONValue]] {
        var rows: [[String: JSONValue]] = []
        let fxExecutable = selectedFX?.appendingPathComponent("Contents/MacOS/steamac-vm")
        let fxState: String
        if let fxExecutable, CoreFS.isRegularExecutable(fxExecutable) {
            fxState = integrity?["state"]?.text == "verified" ? "ready" : "unverified"
        } else {
            fxState = selectedFX == nil ? "missing" : "invalid"
        }
        rows.append(["id": .string("fx"), "name": .string("FX Steam Launcher"),
                     "version": .string(selectedFX.flatMap(bundleVersion) ?? "unknown"), "state": .string(fxState)])
        let gvproxy = LaunchResources.gvproxyBinary
        rows.append(["id": .string("gvproxy"), "name": .string("gvproxy (bundled)"),
                     "version": .string("bundled"), "state": .string(LaunchResources.gvproxyState().state)])
        rows.append(["id": .string("ssh"), "name": .string("OpenSSH"),
                     "version": .string(sshVersion() ?? "unknown"),
                     "state": .string(FileManager.default.isExecutableFile(atPath: "/usr/bin/ssh") ? "ready" : "missing")])
        rows.append(["id": .string("node"), "name": .string("Node.js"),
                     "version": .string("not required"), "state": .string("not_required")])
        for name in ["Steam", "FEX", "Proton-JE", "EAC", "Multiplayer"] {
            rows.append(["id": .string(name.lowercased()), "name": .string(name),
                         "version": .string("unknown"), "state": .string("unverified")])
        }
        return rows
    }

    static func sshVersion() -> String? {
        guard let result = try? CoreProcess.run("/usr/bin/ssh", ["-V"], timeout: 5) else { return nil }
        let text = (result.stderr.isEmpty ? result.stdout : result.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    static func bundleVersion(_ app: URL) -> String? {
        let info = app.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: info, options: .mappedIfSafe),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return plist["CFBundleShortVersionString"] as? String
    }

    static func summary(selectedFX: URL?) -> [String: JSONValue] {
        let rows = items(selectedFX: selectedFX)
        let local = rows.filter { $0["state"]?.text != "unverified" }
        return ["items": .array(local.map { .object($0) }),
                "missing_count": .number(Double(local.filter { $0["state"]?.text == "missing" }.count)),
                "attention_count": .number(Double(local.filter { ["invalid", "unknown"].contains($0["state"]?.text ?? "") }.count)),
                "scope": .string("host_prerequisites_only"),
                "ready": .bool(local.allSatisfy { ["ready", "not_required"].contains($0["state"]?.text ?? "") })]
    }
}
