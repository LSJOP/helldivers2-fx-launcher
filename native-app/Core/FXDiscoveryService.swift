import Foundation

/// App-bundled launch resources. The modified gvproxy build is redistributed under
/// Apache-2.0 with its license and provenance recorded in THIRD_PARTY_NOTICES.md.
enum LaunchResources {
    static let gvproxySHA256 = "27136dd87a6e8c35c2607077a6303082e577751a9e31ebcaa1bd81c93cc58444"
    static let wrapperSHA256 = "80dca2b7d0b04dae44f46b4b6dc9e2735434fdeaa241925f8061613498911d3d"
    static let fxPublisherRequirement = "anchor apple generic and identifier \"es.fxgam.steamac\" and certificate leaf[subject.OU] = \"V25VKGTW55\""

    static var directory: URL? {
        if let override = ProcessInfo.processInfo.environment["HD2FX_LAUNCH_RESOURCES"], !override.isEmpty {
            let url = URL(fileURLWithPath: override, isDirectory: true)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent("launch", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
    static var gvproxyBinary: URL? { directory?.appendingPathComponent("gvproxy-eim") }
    static var wrapper: URL? { directory?.appendingPathComponent("gvproxy-eim-wrapper") }

    struct State: Sendable {
        let state: String
        let actual: String?
        let expected: String
        let path: String?
    }

    static func gvproxyState() -> State {
        guard let binary = gvproxyBinary else { return State(state: "missing", actual: nil, expected: gvproxySHA256, path: nil) }
        let (digest, fileState) = CoreHash.digestFile(binary.deletingLastPathComponent(), relative: "gvproxy-eim", limit: 64 * 1024 * 1024)
        guard let digest else { return State(state: fileState, actual: nil, expected: gvproxySHA256, path: binary.path) }
        return State(state: digest == gvproxySHA256 ? "ready" : "hash_mismatch", actual: digest, expected: gvproxySHA256, path: binary.path)
    }

    static func wrapperState() -> State {
        guard let wrapper else { return State(state: "missing", actual: nil, expected: wrapperSHA256, path: nil) }
        let (digest, fileState) = CoreHash.digestFile(wrapper.deletingLastPathComponent(), relative: "gvproxy-eim-wrapper", limit: 64 * 1024)
        guard let digest else { return State(state: fileState, actual: nil, expected: wrapperSHA256, path: wrapper.path) }
        return State(state: digest == wrapperSHA256 ? "ready" : "hash_mismatch", actual: digest, expected: wrapperSHA256, path: wrapper.path)
    }

    static func report() -> [String: JSONValue] {
        let binary = gvproxyState(), wrapper = wrapperState()
        func row(_ name: String, _ value: State, kind: String) -> JSONValue {
            .object(["file": .string(name), "kind": .string(kind), "actual_sha256": value.actual.map { .string($0) } ?? .null,
                     "expected_sha256": .string(value.expected), "state": .string(value.state),
                     "actual_path": value.path.map { .string($0) } ?? .null])
        }
        let rows = [row("gvproxy-eim", binary, kind: "binary"), row("gvproxy-eim-wrapper", wrapper, kind: "wrapper")]
        return ["bundled": .bool(true), "resource_files": .array(rows),
                "archive_files_match": .bool(binary.state == "ready" && wrapper.state == "ready"),
                "legacy_replaced_native": .array([.string("launcher-20261026/steam-cdp.mjs"), .string("tools/check_node.cjs")]),
                "scope": .string("app_bundle_resources_only")]
    }

    static func verifiedForLaunch() throws -> (binary: URL, wrapper: URL) {
        let binary = gvproxyState(), wrapper = wrapperState()
        guard binary.state == "ready" else { throw CoreError("GVPROXY_UNAVAILABLE", ["state": .string(binary.state)]) }
        guard wrapper.state == "ready", let wrapperURL = wrapper.path.map({ URL(fileURLWithPath: $0) }) else {
            throw CoreError("GVPROXY_UNAVAILABLE", ["state": .string(wrapper.state)])
        }
        guard let binaryURL = binary.path.map({ URL(fileURLWithPath: $0) }) else { throw CoreError("GVPROXY_UNAVAILABLE") }
        return (binaryURL, wrapperURL)
    }
}

/// Bounded, metadata-only FX discovery. A candidate is never a launch or gameplay claim.
enum FXDiscoveryService {
    struct Identity: Sendable {
        let path: String
        let name: String
        let version: String
        let bundleIdentifier: String
        let executable: URL
        let valid: Bool
    }

    static func applicationsDirectories() -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         CoreFS.home().appendingPathComponent("Applications", isDirectory: true)]
    }

    static func identity(of raw: String) -> Identity? {
        guard !raw.isEmpty, raw.count <= 4096, !raw.contains("\0") else { return nil }
        let app = URL(fileURLWithPath: raw).standardizedFileURL
        guard app.path.hasPrefix("/"), app.pathExtension.lowercased() == "app" else { return nil }
        if FileManager.default.isSymbolicLink(atPath: app.path) { return nil }
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        let macos = contents.appendingPathComponent("MacOS", isDirectory: true)
        let executable = macos.appendingPathComponent("steamac-vm")
        if FileManager.default.isSymbolicLink(atPath: contents.path) || FileManager.default.isSymbolicLink(atPath: macos.path) { return nil }
        guard CoreFS.isRegularExecutable(executable) else { return nil }
        let infoURL = contents.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoURL, options: .mappedIfSafe), data.count <= CoreLimits.maxSmallFile,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        let version = (plist["CFBundleShortVersionString"] as? String) ?? "unknown"
        let valid = bundleIdentifier == "es.fxgam.steamac"
        return Identity(path: app.path, name: app.lastPathComponent,
                        version: valid ? version : "unknown",
                        bundleIdentifier: bundleIdentifier ?? "unknown",
                        executable: executable, valid: valid)
    }

    static func candidate(_ identity: Identity) -> [String: JSONValue] {
        let parent = URL(fileURLWithPath: identity.path).deletingLastPathComponent().path
        let location = parent == "/Applications" ? "/Applications" : parent.hasPrefix(CoreFS.home().path) ? "~/Applications" : parent
        return ["path": .string(identity.path), "name": .string(identity.name),
                "version": .string(identity.version),
                "bundle_identifier": .string(identity.bundleIdentifier),
                "structure": .string(identity.valid ? "metadata_valid" : "unverified"),
                "identity_valid": .bool(identity.valid),
                "location": .string(location),
                "launch": .string("unverified"), "eac": .string("unverified"),
                "multiplayer": .string("unverified")]
    }

    static func scan(selectedPaths: [String], runtimeRoot: String?) -> [String: JSONValue] {
        var candidates: [[String: JSONValue]] = []
        var seenInodes = Set<String>()
        var incomplete = false
        var issues: [JSONValue] = []
        for directory in applicationsDirectories() {
            do {
                let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path)
                if entries.count > CoreLimits.maxScanEntries { incomplete = true }
                for name in entries.prefix(CoreLimits.maxScanEntries) where name.lowercased().hasSuffix(".app") {
                    let app = directory.appendingPathComponent(name)
                    guard let identity = identity(of: app.path), identity.valid else { continue }
                    let attributes = try? FileManager.default.attributesOfItem(atPath: identity.executable.path)
                    let inode = [(attributes?[.systemNumber] as? NSNumber)?.stringValue,
                                 (attributes?[.systemFileNumber] as? NSNumber)?.stringValue].compactMap { $0 }.joined(separator: ":")
                    if !inode.isEmpty {
                        if seenInodes.contains(inode) { continue }
                        seenInodes.insert(inode)
                    }
                    candidates.append(candidate(identity))
                }
            } catch let error as NSError where error.code == NSFileReadNoSuchFileError {
                continue
            } catch {
                incomplete = true
                issues.append(.string("DIRECTORY_UNAVAILABLE"))
            }
        }
        var hints = selectedPaths
        if let runtimeRoot, !runtimeRoot.isEmpty {
            hints.append(runtimeRoot + "/performance-stutter-20261027/FX HUD隔离诊断.app")
        }
        var seenPaths = Set<String>()
        for hint in hints {
            guard let identity = identity(of: hint), !seenPaths.contains(identity.path) else { continue }
            seenPaths.insert(identity.path)
            candidates.append(candidate(identity))
        }
        return ["candidates": .array(candidates.map { .object($0) }),
                "scan_incomplete": .bool(incomplete),
                "issues": .array(issues),
                "scope": .string("two_shallow_application_directories_metadata_only"),
                "compatibility": .string("unverified"),
                "runtime_selection": .string("not_required_bundled_resources")]
    }

    /// Exact target inspection: selected bundle metadata + bundled launch resources.
    static func launchTarget(fxPath: String?) -> [String: JSONValue] {
        let resources = LaunchResources.report()
        guard let fxPath, let identity = identity(of: fxPath) else {
            var result = resources
            result["target_root"] = .string("")
            result["target_kind"] = .string("none")
            result["fx_executable_present"] = .bool(false)
            result["fx_path"] = .string("")
            result["fx_version"] = .string("unknown")
            result["scope"] = .string("selected_target_file_metadata_only")
            result["guest"] = .string("unverified")
            result["eac"] = .string("unverified")
            result["multiplayer"] = .string("unverified")
            result["launch"] = .string("unverified")
            return result
        }
        var result = resources
        result["target_root"] = .string(identity.path)
        result["target_kind"] = .string("fx_app_bundle")
        result["fx_executable_present"] = .bool(identity.valid)
        result["fx_path"] = .string(identity.path)
        result["fx_version"] = .string(identity.version)
        result["scope"] = .string("selected_target_file_metadata_only")
        result["guest"] = .string("unverified")
        result["eac"] = .string("unverified")
        result["multiplayer"] = .string("unverified")
        result["launch"] = .string("unverified")
        return result
    }

    /// Hash-pinned history or a bundle sealed by the verified FX publisher.
    static func integrity(app: URL) -> [String: JSONValue] {
        let executable = app.appendingPathComponent("Contents/MacOS/steamac-vm")
        guard let digest = try? CoreHash.sha256File(executable) else {
            return ["fx_path": .string(app.path), "actual_sha256": .null,
                    "state": .string("missing"), "trust": .string("unverified")]
        }
        let signature = (try? CoreProcess.run("/usr/bin/codesign",
                                             ["--verify", "--deep", "--strict", "-R=" + LaunchResources.fxPublisherRequirement, app.path],
                                             timeout: 20))?.status == 0
        let fresh = try? CoreHash.sha256File(executable)
        var result: [String: JSONValue] = ["fx_path": .string(app.path),
                                           "actual_path": .string(executable.path),
                                           "actual_sha256": .string(digest),
                                           "trust": .string("unverified"),
                                           "publisher_signature": .bool(signature),
                                           "state": .string("unverified")]
        if signature && fresh == digest {
            result["state"] = .string("verified")
            result["trust"] = .string("fx_publisher_signature")
        } else if !signature {
            result["state"] = .string("signature_invalid")
        }
        return result
    }
}
