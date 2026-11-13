import Foundation

// Isolated native-core checks. Uses a temporary Application Support root and a
// temporary resource directory; never reads or writes real FX preferences.
enum CheckFailure: Error { case failed(String) }

var passed = 0
var failed = 0
func check(_ condition: Bool, _ name: String) {
    if condition { passed += 1; print("PASS \(name)") }
    else { failed += 1; print("FAIL \(name)") }
}
func checkThrows(_ code: String, _ name: String, _ body: () throws -> Void) {
    do { try body(); failed += 1; print("FAIL \(name) (no error)") }
    catch let error as CoreError { check(error.code == code, "\(name) [\(error.code)]") }
    catch let error as ErrorState { check(error.code == code, "\(name) [\(error.code)]") }
    catch { failed += 1; print("FAIL \(name) (unexpected)") }
}

func runChecks() {
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hd2-native-checks-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    setenv("HD2FX_NATIVE_TEST_ROOT", root.path, 1)
    let resources = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/launch")
    setenv("HD2FX_LAUNCH_RESOURCES", resources.path, 1)
    defer { try? FileManager.default.removeItem(at: root) }

    for method in ["first_run_fex_build", "first_run_fex_install", "first_run_fex_recover"] {
        checkThrows("CONFIRMATION_REQUIRED", "FEX action requires explicit initiation: " + method) {
            _ = try NativeCoreService.perform(method, params: [:], context: CoreContext(timeout: 1), onEvent: nil)
        }
    }

    let fexSnapshot = DeploymentSnapshot(target: "fixture", boot: UUID().uuidString, revision: "fixture", fxVersion: "fixture", osVersion: "fixture", architecture: "aarch64", steamRunning: false, gameRunning: false, freeBytes: 0,
        facts: ["fx_path": "/fixture/FX.app", "machine_id": String(repeating: "a", count: 32), "fx_executable_sha256": String(repeating: "b", count: 64), "ssh_connection": String(repeating: "c", count: 64)], values: [:])
    var fexRecord = fexSnapshot.facts.mapValues(JSONValue.string)
    fexRecord["built"] = .bool(true)
    fexRecord["audit"] = .object(["ready": .bool(true), "source": .string("87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8"), "patch": .string("85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926"), "executable_sha256": .string(LaunchService.verifiedFEX)])
    fexRecord["installation"] = .object(["verified": .bool(true), "installed_manifest": .string(String(repeating: "d", count: 64))])
    check(FEXWorkflow.installedDigest(fexRecord, snapshot: fexSnapshot) != nil, "FEX full installed manifest has bound build approval")
    var wrongFEXRecord = fexRecord; wrongFEXRecord["machine_id"] = .string(String(repeating: "e", count: 32))
    check(FEXWorkflow.installedDigest(wrongFEXRecord, snapshot: fexSnapshot) == nil, "FEX approval never crosses Guest identity")
    wrongFEXRecord = fexRecord; wrongFEXRecord["built"] = .bool(false)
    check(FEXWorkflow.installedDigest(wrongFEXRecord, snapshot: fexSnapshot) == nil, "Guest provenance alone cannot establish FEX approval")
    wrongFEXRecord = fexRecord; wrongFEXRecord["installation"] = .object(["verified": .bool(true)])
    check(FEXWorkflow.installedDigest(wrongFEXRecord, snapshot: fexSnapshot) == nil, "FEX executable alone is not a complete installed manifest")

    var customRecord = fexRecord
    var customAudit = customRecord["audit"]!.object
    customAudit["executable_sha256"] = .string(String(repeating: "e", count: 64))
    customRecord["audit"] = .object(customAudit)
    check(FEXWorkflow.installedDigest(customRecord, snapshot: fexSnapshot) != nil, "scoped build provenance accepts a different executable hash")
    for status in ["normal", "compatible"] {
        var observed = fexSnapshot
        observed.facts["fex_status"] = status
        check((try? FEXWorkflow.requireCompatible(observed)) != nil, "runtime state accepted: " + status)
    }
    for reason in ["FEX_CONFIRMATION_REQUIRED", "FEX_CHANGED", "FEX_RUNTIME_FAILED", "FEX_INTEGRITY_FAILED"] {
        var observed = fexSnapshot
        observed.facts["fex_status"] = "repair"
        observed.facts["fex_reason"] = reason
        observed.facts["fex_runtime"] = "ready"
        checkThrows(reason, "fresh failure cannot inherit stale readiness: " + reason) { try FEXWorkflow.requireCompatible(observed) }
    }
    var installedFEX = fexSnapshot
    installedFEX.facts["fex_runtime"] = "ready"
    let existingPlan = DeploymentPlanBuilder.build(installedFEX, profile: try! EnvironmentProfile.load(resources.deletingLastPathComponent().appendingPathComponent("environment-profile-v1.json")))
    check(existingPlan.operations.first(where: { $0.component == "fex" })?.detectionPassed == true,
          "ready installed FEX does not require a candidate archive")
    installedFEX.facts["fex_runtime"] = "failed"
    let brokenPlan = DeploymentPlanBuilder.build(installedFEX, profile: try! EnvironmentProfile.load(resources.deletingLastPathComponent().appendingPathComponent("environment-profile-v1.json")))
    check(brokenPlan.operations.first(where: { $0.component == "fex" })?.detectionPassed == false,
          "failed installed FEX never becomes ready from candidate metadata")
    let managed = ["launch": "%command%", "tool": "proton", "ipv6.all": "0"]
    let fingerprint = SSHEnvironmentBackend.configurationFingerprint(values: managed, configurationRevision: "revision")
    check(fingerprint == SSHEnvironmentBackend.configurationFingerprint(values: managed, configurationRevision: "revision"),
          "deployment revision uses managed values independently of Steam VDF metadata")
    var drift = managed; drift["tool"] = "external"
    check(fingerprint != SSHEnvironmentBackend.configurationFingerprint(values: drift, configurationRevision: "revision"),
          "external managed-value drift changes deployment revision")
    check(fingerprint != SSHEnvironmentBackend.configurationFingerprint(values: managed, configurationRevision: "other"),
          "launcher configuration drift changes deployment revision")
    // MARK: SHA-256 / bounded file reads
    check(CoreHash.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", "sha256 abc")
    check(CoreHash.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "sha256 empty")
    let small = root.appendingPathComponent("digest.txt")
    try! Data("payload".utf8).write(to: small)
    check(CoreHash.digestFile(root, relative: "digest.txt").0 == CoreHash.sha256(Data("payload".utf8)), "digestFile")
    let link = root.appendingPathComponent("link.txt")
    try! FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: small.path)
    check(CoreHash.digestFile(root, relative: "link.txt").1 == "unsafe_path", "symlink rejected")

    // MARK: Bundled launch resources
    let resourceState = LaunchResources.gvproxyState()
    check(resourceState.state == "ready", "bundled gvproxy hash")
    check(LaunchResources.wrapperState().state == "ready", "bundled wrapper hash")
    check(LaunchResources.report()["archive_files_match"]?.boolean == true, "resource report matches")
    let nonExecutable = root.appendingPathComponent("non-executable", isDirectory: true)
    try! FileManager.default.createDirectory(at: nonExecutable, withIntermediateDirectories: true)
    for name in ["gvproxy-eim", "gvproxy-eim-wrapper"] {
        let destination = nonExecutable.appendingPathComponent(name)
        try! FileManager.default.copyItem(at: resources.appendingPathComponent(name), to: destination)
        try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
    setenv("HD2FX_LAUNCH_RESOURCES", nonExecutable.path, 1)
    check(LaunchResources.gvproxyState().state == "not_executable", "non-executable gvproxy detected")
    check(LaunchResources.wrapperState().state == "not_executable", "non-executable wrapper detected")
    checkThrows("GVPROXY_UNAVAILABLE", "launch refuses non-executable resource") { _ = try LaunchResources.verifiedForLaunch() }
    let tamper = root.appendingPathComponent("launch", isDirectory: true)
    try! FileManager.default.createDirectory(at: tamper, withIntermediateDirectories: true)
    try! Data("tampered".utf8).write(to: tamper.appendingPathComponent("gvproxy-eim"))
    try! Data("x".utf8).write(to: tamper.appendingPathComponent("gvproxy-eim-wrapper"))
    setenv("HD2FX_LAUNCH_RESOURCES", tamper.path, 1)
    check(LaunchResources.gvproxyState().state == "hash_mismatch", "tampered resource detected")
    checkThrows("GVPROXY_UNAVAILABLE", "launch refuses tampered resource") { _ = try LaunchResources.verifiedForLaunch() }
    setenv("HD2FX_LAUNCH_RESOURCES", resources.path, 1)
    let missingDirectory = root.appendingPathComponent("missing-resources")
    _ = missingDirectory
    setenv("HD2FX_LAUNCH_RESOURCES", missingDirectory.path, 1)
    check(LaunchResources.gvproxyState().state == "missing", "missing resource detected")
    setenv("HD2FX_LAUNCH_RESOURCES", resources.path, 1)

    // MARK: FX fixture + discovery
    func makeApp(_ name: String, bundleID: String, version: String) throws -> URL {
        let app = root.appendingPathComponent("\(name).app")
        let macos = app.appendingPathComponent("Contents/MacOS", isDirectory: true)
        try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundleExecutable": "steamac-vm"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: macos.appendingPathComponent("steamac-vm"))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macos.appendingPathComponent("steamac-vm").path)
        return app
    }
    let fx194 = try! makeApp("FX194", bundleID: "es.fxgam.steamac", version: "1.9.4")
    let fx198 = try! makeApp("FX198", bundleID: "es.fxgam.steamac", version: "1.9.8")
    let foreign = try! makeApp("Other", bundleID: "com.example.other", version: "1.0")
    check(FXDiscoveryService.identity(of: fx194.path)?.version == "1.9.4", "FX 1.9.4 identity")
    check(FXDiscoveryService.identity(of: fx198.path)?.version == "1.9.8", "FX 1.9.8 identity")
    check(FXDiscoveryService.identity(of: foreign.path)?.valid == false, "foreign bundle rejected")
    check(FXDiscoveryService.identity(of: "/tmp/not-an-app.txt") == nil, "non-app path rejected")
    let scan = FXDiscoveryService.scan(selectedPaths: [fx194.path, fx198.path, fx194.path], runtimeRoot: nil)
    let fixtureCount = (scan["candidates"]?.array ?? []).filter { ($0.object["path"]?.text ?? "").hasPrefix(root.path) }.count
    check(fixtureCount == 2, "duplicate hint de-duplicated")
    check(scan["scope"]?.text == "two_shallow_application_directories_metadata_only", "scan scope explicit")
    let overlap = FXDiscoveryService.scan(selectedPaths: [fx194.path, fx198.path], runtimeRoot: nil, directories: [root])
    let overlapRows = overlap["candidates"]?.array ?? []
    check(overlapRows.count == 2, "selected FX already discovered is not duplicated")
    let target = FXDiscoveryService.launchTarget(fxPath: fx198.path)
    check(target["fx_version"]?.text == "1.9.8", "launch target version")
    check(target["archive_files_match"]?.boolean == true, "launch target resources")
    check(target["launch"]?.text == "unverified", "launch target not launch proof")
    check(FXDiscoveryService.launchTarget(fxPath: "/tmp/missing.app")["fx_executable_present"]?.boolean == false, "missing target fails closed")

    // A renamed local test copy remains selectable and launchable without claiming publisher trust.
    let localFX = try! makeApp("Local FX", bundleID: "es.fxgam.steamtc", version: "1.9.9")
    check(FXDiscoveryService.identity(of: localFX.path)?.valid == true, "local test identity recognized")
    let localScan = FXDiscoveryService.scan(selectedPaths: [], runtimeRoot: nil, directories: [root])
    check((localScan["candidates"]?.array ?? []).contains { $0.object["path"]?.text == localFX.path && $0.object["local_test_copy"]?.boolean == true }, "local test copy visible with honest marker")
    let localExe = localFX.appendingPathComponent("Contents/MacOS/steamac-vm")
    try! FileManager.default.removeItem(at: localExe)
    try! FileManager.default.copyItem(at: URL(fileURLWithPath: "/usr/bin/true"), to: localExe)
    let signing = try! CoreProcess.run("/usr/bin/codesign", ["--force", "--sign", "-", "--identifier", "es.fxgam.steamtc", localFX.path], timeout: 20)
    check(signing.status == 0, "isolated local fixture signed")
    let localIntegrity = FXDiscoveryService.integrity(app: localFX)
    check(localIntegrity["state"]?.text == "local_copy" && localIntegrity["publisher_signature"]?.boolean == false, "local seal does not claim publisher verification")
    check(FXDiscoveryService.launchAllowed(localIntegrity), "local sealed copy allowed to start")
    check(!FXDiscoveryService.launchAllowed(["state": .string("signature_invalid")]), "broken seal never accepted")
    let originalInfo = try! Data(contentsOf: localFX.appendingPathComponent("Contents/Info.plist"))
    try! (originalInfo + Data("\n<!-- changed after signing -->\n".utf8)).write(to: localFX.appendingPathComponent("Contents/Info.plist"))
    check(!FXDiscoveryService.launchAllowed(FXDiscoveryService.integrity(app: localFX)), "modified sealed resource rejected")

    // MARK: Configuration read/save/backup/restore
    let read = try! ConfigurationService.resultRead()
    check(read["configuration"]?.object["version"]?.integer == 1, "default settings")
    let revision = read["revision"]?.text ?? ""
    check(revision == CoreHash.sha256(Data()), "empty-file revision")
    let saved = try! ConfigurationService.save(patch: .object(["ssh": .object(["port": .number(2223)])]), expectedRevision: revision)
    check(saved["saved"]?.boolean == true, "settings saved")
    check(saved["backup"]?.text == nil, "missing original has no backup")
    let afterSave = try! ConfigurationService.read()
    check(afterSave.configuration["ssh"]?.object["port"]?.integer == 2223, "settings value written")
    checkThrows("CONFIG_CHANGED", "stale revision rejected") {
        _ = try ConfigurationService.save(patch: .object(["ssh": .object(["port": .number(2224)])]), expectedRevision: revision)
    }
    checkThrows("INVALID_ARGUMENT", "port range validated") {
        _ = try ConfigurationService.save(patch: .object(["ssh": .object(["port": .number(70000)])]),
                                          expectedRevision: afterSave.revision)
    }
    checkThrows("INVALID_ARGUMENT", "unknown field rejected") {
        _ = try ConfigurationService.save(patch: .object(["unknown": .bool(true)]), expectedRevision: afterSave.revision)
    }
    checkThrows("SENSITIVE_CONFIGURATION", "secret rejected") {
        _ = try ConfigurationService.save(patch: .object(["appearance": .object(["language": .string("password=abc123")])]),
                                          expectedRevision: afterSave.revision)
    }
    let blankPatch = try! ConfigurationService.connectionPatch(host: " ", port: "", username: "\t", current: ConfigurationService.sshDefaults)
    check(blankPatch.isEmpty, "blank SSH fields keep defaults without writes")
    let onlyPort = try! ConfigurationService.connectionPatch(host: "", port: " 2223 ", username: "", current: ConfigurationService.sshDefaults)
    check(onlyPort == ["port": .number(2223)], "only populated SSH field changes")
    let customSSH: [String: JSONValue] = ["host": .string("test-vm.local"), "port": .number(2223), "username": .string("customuser")]
    check(try! ConfigurationService.connectionPatch(host: "", port: "", username: "", current: customSSH).isEmpty, "blank fields preserve saved custom connection")
    let effectiveDefaults = try! ConfigurationService.validatedSSH([:])
    check(effectiveDefaults["host"]?.text == "127.0.0.1" && effectiveDefaults["port"]?.integer == 2222 && effectiveDefaults["username"]?.text == "steamos", "initial SSH defaults need no manual input")
    for invalidPort in ["abc", "0", "65536", "22.5", "２２２２"] {
        checkThrows("INVALID_ARGUMENT", "invalid populated SSH port rejected") { _ = try ConfigurationService.connectionPatch(host: "", port: invalidPort, username: "", current: ConfigurationService.sshDefaults) }
    }
    let endpoint = try! ConfigurationService.validatedSSH(["host": .string("test-vm.local"), "port": .number(2223), "username": .string("steamos")])
    check(endpoint["host"]?.text == "test-vm.local" && endpoint["port"]?.integer == 2223, "custom SSH endpoint accepted")
    for host in ["-oProxyCommand=bad", "host; command", "user@host", ""] {
        checkThrows("INVALID_ARGUMENT", "unsafe SSH endpoint rejected") { _ = try ConfigurationService.validatedSSH(["host": .string(host)]) }
    }
    checkThrows("INVALID_ARGUMENT", "SSH forwarding port collision rejected") {
        _ = try ConfigurationService.validatedSSH(["port": .number(18094)])
    }
    let snapshot = try! ConfigurationService.snapshot(reason: "checks")
    check(FileManager.default.fileExists(atPath: snapshot["path"]?.text ?? ""), "manual backup file")
    let secondSave = try! ConfigurationService.save(patch: .object(["ssh": .object(["port": .number(2224)])]),
                                                    expectedRevision: afterSave.revision)
    check(secondSave["backup"]?.text != nil, "existing settings backed up before write")
    let restoredOK = try! ConfigurationService.restore(path: snapshot["path"]!.text!, confirmed: true)
    check(restoredOK["restored"]?.boolean == true, "settings restored")
    check(try! ConfigurationService.read().configuration["ssh"]?.object["port"]?.integer == 2223, "restored value")
    checkThrows("CONFIRMATION_REQUIRED", "restore requires confirmation") {
        _ = try ConfigurationService.restore(path: snapshot["path"]!.text!, confirmed: false)
    }
    checkThrows("UNSAFE_PATH", "restore outside backup folder rejected") {
        _ = try ConfigurationService.restore(path: "/etc/passwd", confirmed: true)
    }
    check(ConfigurationService.backups()["backups"]?.array.isEmpty == false, "backup list")

    // MARK: Performance scoped preferences (in-memory store)
    let store = MemoryPreferencesStore(["cpus": .number(8), "memMiB": .number(8192),
                                        "vulkanDriver": .string("kosmickrisp"),
                                        "metalHUD": .bool(false), "superResolution": .bool(false),
                                        "unrelated": .string("keep")])
    let rules = PerformanceRules(version: "future-build", cpuMin: 1, cpuMax: 12, memoryMin: 4096, memoryMax: 12288,
                                 memoryStep: 256, drivers: ["kosmickrisp", "moltenvk"],
                                 writable: ["cpus", "memMiB", "vulkanDriver", "metalHUD"])
    let snapshotResult = try! PerformanceConfigurationService.snapshot(store: store, rules: rules)
    check(snapshotResult["current"]?.object["cpus"]?.integer == 8, "performance snapshot")
    check(snapshotResult["effective"]?.text == "unverified", "performance not claimed effective")
    let values: [String: JSONValue] = ["cpus": .number(10), "memMiB": .number(10240),
                                       "vulkanDriver": .string("moltenvk"), "metalHUD": .bool(true),
                                       "superResolution": .bool(false)]
    let preview = try! PerformanceConfigurationService.preview(values: values, revision: snapshotResult["revision"]!.text!,
                                                               restore: false, store: store, rules: rules, probe: {})
    check(preview["changes"]?.object.count == 4, "preview changes")
    let applied = try! PerformanceConfigurationService.commit(values: values, revision: snapshotResult["revision"]!.text!,
                                                              token: preview["token"]!.text!, restore: false,
                                                              store: store, rules: rules, probe: {}, emit: { _ in })
    check(applied["status"]?.text == "saved", "performance saved")
    check(store.box.values["cpus"]?.integer == 10, "preference write")
    check(store.box.values["unrelated"]?.text == "keep", "unrelated preference preserved")
    check(applied["can_restore"]?.boolean == true, "restore receipt recorded")
    let restorePreview = try! PerformanceConfigurationService.preview(values: nil, revision: applied["revision"]!.text!,
                                                                      restore: true, store: store, rules: rules, probe: {})
    let restoredPerformance = try! PerformanceConfigurationService.commit(values: nil, revision: applied["revision"]!.text!,
                                                                         token: restorePreview["token"]!.text!, restore: true,
                                                                         store: store, rules: rules, probe: {}, emit: { _ in })
    check(restoredPerformance["status"]?.text == "restored", "performance restored")
    check(store.box.values["cpus"]?.integer == 8, "restored preference value")
    checkThrows("PERF_RANGE", "out-of-range memory rejected") {
        _ = try PerformanceConfigurationService.preview(values: ["cpus": .number(10), "memMiB": .number(999),
                                                                 "vulkanDriver": .string("kosmickrisp"),
                                                                 "metalHUD": .bool(false), "superResolution": .bool(false)],
                                                        revision: try PerformanceConfigurationService.snapshot(store: store, rules: rules)["revision"]!.text!,
                                                        restore: false, store: store, rules: rules, probe: {})
    }
    checkThrows("PERF_CONFLICT", "stale performance revision rejected") {
        _ = try PerformanceConfigurationService.preview(values: values, revision: "stale", restore: false,
                                                        store: store, rules: rules, probe: {})
    }

    // MARK: Guest protocol parsing
    let guestFixture = #"{"boot":"abc","marker":true,"ipv6":{"all":"1","default":"1","eth0":"1","lo":"1"},"proxy":"none","service":"stopped","game_count":0,"steam_count":0,"steam_logged_on":false,"apps":"","vulkan":true,"fex":"h","ntdll":"n","tool":"proton-je-11.0-20261014-3","launch":"","wine_core":{},"uid":1000}"#
    let guest = try! GuestService.parse(guestFixture, expected: "GUEST_INSPECTION_FAILED")
    check(guest["boot"]?.text == "abc", "guest state parsed")
    check(guest["service"]?.text == "stopped", "guest service parsed")
    checkThrows("GUEST_INSPECTION_FAILED", "corrupt guest output rejected") {
        _ = try GuestService.parse("not json", expected: "GUEST_INSPECTION_FAILED")
    }

    // MARK: Native dispatch contract
    let handshake = try! NativeCoreService.perform("handshake", params: [:], context: CoreContext(timeout: 5), onEvent: nil)
    check(handshake.result["protocol_min"]?.integer == 1, "handshake protocol")
    check(handshake.result["python_required"]?.boolean == false, "handshake no python")
    let system = try! NativeCoreService.perform("get_system_info", params: [:], context: CoreContext(timeout: 5), onEvent: nil)
    check(system.result["arch"]?.text == "arm64", "system arch")
    check(system.result["native_runtime"]?.text == "Swift Native Core", "native runtime")
    let dependencies = try! NativeCoreService.perform("get_dependencies", params: [:], context: CoreContext(timeout: 5), onEvent: nil)
    let dependencyRows = dependencies.result["items"]?.array.compactMap(\.object) ?? []
    check(!dependencyRows.contains(where: { $0["name"]?.text == "Python" }), "no Python dependency row")
    check((dependencies.result["items"]?.array.count ?? 0) > 0, "dependency rows")
    let catalog = try! NativeCoreService.perform("get_legacy_catalog", params: [:], context: CoreContext(timeout: 5), onEvent: nil)
    check((catalog.result["operations"]?.array.count ?? 0) > 10, "native catalog")
    check(catalog.result["runtime"]?.text == "swift_native_core", "catalog runtime")
    let settings = try! NativeCoreService.perform("read_configuration", params: [:], context: CoreContext(timeout: 5), onEvent: nil)
    check(settings.result["revision"]?.text != nil, "dispatch read configuration")
    checkThrows("CONFIRMATION_REQUIRED", "dispatch confirmation gate") {
        _ = try NativeCoreService.perform("save_configuration", params: ["expected_revision": .string("x")],
                                          context: CoreContext(timeout: 5), onEvent: nil)
    }

    // MARK: Localization catalogs
    let catalogURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/native-locales.json")
    let catalogs = (try? JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: [String: String]]) ?? [:]
    check(catalogs.count == 10, "ten language catalogs")
    let nativeKeys = ["ui.native.runtime", "ui.native.engine", "ui.native.noPython", "ui.native.resources",
                      "ui.native.bundled", "ui.native.backup", "ui.native.backupHelp",
                      "ui.native.backupCreate", "ui.native.backupNone", "ui.native.backupRestore",
                      "ui.native.backupDone", "ui.native.restoreDone"]
    check(catalogs.allSatisfy { pair in nativeKeys.allSatisfy { pair.value[$0] != nil } }, "native keys complete")

    print("TOTAL \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
}

@main
struct NativeCoreChecksEntry {
    static func main() { runChecks() }
}
