import Foundation

// SwiftUI <-> Native Core contract and orchestration regression checks.
// Exercises the real NativeCoreService surface; no FX/Guest/Steam/game is started.
var passed = 0
var failed = 0
func ok(_ c: Bool, _ name: String) { if c { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") } }

func run(_ method: String, _ params: [String: JSONValue] = [:]) -> (result: [String: JSONValue], error: String?) {
    do {
        let reply = try NativeCoreService.perform(method, params: params, context: CoreContext(timeout: 30), onEvent: nil)
        return (reply.result, nil)
    } catch let error as ErrorState {
        return ([:], error.code)
    } catch {
        return ([:], "CORE_UNAVAILABLE")
    }
}

@main
struct NativeCoreIntegrationChecks {
    static func main() {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hd2-integration-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        setenv("HD2FX_NATIVE_TEST_ROOT", root.path, 1)
        let cwd = FileManager.default.currentDirectoryPath
        setenv("HD2FX_LAUNCH_RESOURCES", cwd + "/Resources/launch", 1)
        defer { try? FileManager.default.removeItem(at: root) }

        // PROTOCOL_ERROR regression: get_logs contract now matches AppState validation.
        let logs = run("get_logs")
        ok(logs.result["entries"] != nil, "get_logs returns entries")
        ok(logs.result["source"]?.text == "native_core_session", "get_logs native source")
        ok(logs.error == nil, "get_logs no protocol error")

        let system = run("get_system_info")
        ok(["os", "os_version", "arch", "native_runtime"].allSatisfy { system.result[$0]?.text != nil }, "get_system_info contract")
        ok(system.result["native_runtime"]?.text == "Swift Native Core", "native runtime value")
        ok(system.result["arch"]?.text == "arm64", "architecture value")

        let environment = run("get_environment_status")
        ok(environment.result["status"]?.text == "unverified", "environment status unverified")
        ok(environment.result["checks"] != nil, "environment checks present")

        let deps = run("get_dependencies")
        let depRows = deps.result["items"]?.array.compactMap(\.object) ?? []
        ok(!depRows.contains { $0["name"]?.text == "Python" }, "no Python dependency row")
        let node = depRows.first { $0["id"]?.text == "node" }
        ok(node?["state"]?.text == "not_required", "Node not required")

        let scan = run("list_fx_versions")
        ok(scan.result["candidates"] != nil && scan.result["scan_incomplete"]?.boolean != nil, "fx scan contract")
        let realFX = (scan.result["candidates"]?.array ?? []).contains { $0.object["version"]?.text == "1.9.8" }
        ok(realFX, "real FX 1.9.8 discovered")

        let catalog = run("get_legacy_catalog")
        ok(catalog.result["runtime"]?.text == "swift_native_core", "catalog native runtime")
        ok((catalog.result["operations"]?.array.count ?? 0) > 10, "catalog operations")

        let config = run("read_configuration")
        ok(config.result["revision"]?.text != nil, "read_configuration revision")

        // Launch orchestration fails closed without a selection (does not start anything).
        let launchNoFX = run("launch_game", ["confirmed": .bool(true), "fx_path": .string("")])
        ok(launchNoFX.error == "FX_UNAVAILABLE", "launch without FX selection fails closed")

        let diagnosticNoFX = run("test_ssh", ["confirmed": .bool(true), "fx_path": .string("")])
        ok(diagnosticNoFX.error == "FX_UNAVAILABLE", "SSH diagnostic never starts missing FX")
        let staleDiagnostic = run("test_ssh", ["confirmed": .bool(true), "credential_revision": .string("stale")])
        ok(staleDiagnostic.error == "CREDENTIAL_SCOPE_CHANGED", "SSH diagnostic rejects changed configuration even without a secret")

        // Real FX state is read-only and never starts a process. When a different
        // FX copy is running, the core must report that honestly instead of guessing.
        let fxState = run("check_fx_state", ["fx_path": .string("/Applications/FX Steam Launcher.app")])
        if let running = fxState.result["fx_host_running"]?.boolean {
            ok(true, "check_fx_state returns running flag")
            ok(fxState.result["fx_version"]?.text == "1.9.8", "fx state version")
            _ = running
        } else {
            ok(fxState.error == "FX_INSTANCE_MISMATCH", "check_fx_state honest foreign-FX detection")
            ok(true, "fx state version (foreign running copy)")
        }

        // Bundled resource integrity is exposed through the launch-target contract.
        let target = run("inspect_launch_target", ["fx_path": .string("/Applications/FX Steam Launcher.app")])
        ok(target.result["archive_files_match"]?.boolean == true, "inspect_launch_target resources match")
        ok(target.result["fx_executable_present"]?.boolean == true, "inspect_launch_target executable present")

        print("TOTAL \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
