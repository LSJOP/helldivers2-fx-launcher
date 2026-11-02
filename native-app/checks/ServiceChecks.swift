import Foundation

// A standalone executable compiled against production services; all fault programs
// are generated in a temporary directory and never exposed in the shipping bridge.
@main struct ServiceChecks {
    static func main() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hd2-service-checks-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let script = URL(fileURLWithPath: CommandLine.arguments[1])
        let real = BridgeConfiguration(python: URL(fileURLWithPath: "/usr/bin/python3"), script: script)
        var passed = 0
        func check(_ condition: Bool, _ name: String) throws {
            guard condition else { throw ErrorState("ASSERTION_FAILED", method: name) }
            passed += 1; print("PASS \(name)")
        }
        func fixture(_ name: String, _ code: String) throws -> BridgeConfiguration {
            let path = directory.appendingPathComponent(name + ".py")
            try code.write(to: path, atomically: true, encoding: .utf8)
            return BridgeConfiguration(python: real.python, script: path)
        }
        func expect(_ code: String, config: BridgeConfiguration, method: String = "get_system_info", timeout: Double = 1) async throws {
            do {
                _ = try await BridgeService().request(method, configuration: config, timeout: timeout)
                throw ErrorState("EXPECTED_FAILURE", method: code)
            } catch let error as ErrorState { try check(error.code == code, "\(code) \(config.script.lastPathComponent)") }
        }
        let handshake = try await BridgeService().request("handshake", configuration: real)
        try check(handshake.result["read_only_default"]?.boolean == true, "real handshake and protocol negotiation")
        let version = try await BridgeService().request("get_launcher_version", configuration: real)
        try check(version.result["version"]?.text != nil && !version.requestID.isEmpty, "real version and matching request_id")
        let prefix = "import json,sys\nr=json.loads(sys.stdin.readline())\n"
        let good = "dict(protocol=1, request_id=r['request_id'], ok=True, result={}, observed_at='now')"
        try await expect("TIMEOUT", config: fixture("timeout", "import time\ntime.sleep(10)\n"), timeout: 0.08)
        try await expect("TIMEOUT", config: fixture("ignores_term", "import signal,time\nsignal.signal(signal.SIGTERM,signal.SIG_IGN)\ntime.sleep(10)\n"), timeout: 0.2)
        try await expect("BRIDGE_EXITED", config: fixture("exit", "raise SystemExit(7)\n"))
        try await expect("PROTOCOL_ERROR", config: fixture("empty", "pass\n"))
        try await expect("PROTOCOL_ERROR", config: fixture("malformed", "print('not json')\n"))
        try await expect("PROTOCOL_ERROR", config: fixture("wrong_id", prefix + "print(json.dumps(dict(protocol=1,request_id='wrong',ok=True,result={},observed_at='now')))\n"))
        try await expect("PROTOCOL_MISMATCH", config: fixture("wrong_protocol", prefix + "print(json.dumps(dict(protocol=2,request_id=r['request_id'],ok=True,result={},observed_at='now')))\n"))
        try await expect("PROTOCOL_MISMATCH", config: fixture("missing_capabilities", prefix + "print(json.dumps(" + good + "))\n"), method: "handshake")
        try await expect("PROTOCOL_ERROR", config: fixture("extra_frame", prefix + "print(json.dumps(" + good + "))\nprint('{}')\n"))
        let streaming = try fixture("streaming", prefix + "print(json.dumps(dict(protocol=1,request_id=r['request_id'],event=dict(stage='preflight',status='running'))))\nprint(json.dumps(" + good + "))\n")
        let progress = ProgressRecorder()
        _ = try await BridgeService().request("launch_game", configuration: streaming, params: ["confirmed": .bool(true)]) { progress.record($0) }
        try check(progress.count == 1, "progress frames delivered before final result")
        try await expect("PROTOCOL_ERROR", config: fixture("foreign_progress", prefix + "print(json.dumps(dict(protocol=1,request_id='foreign',event={})))\nprint(json.dumps(" + good + "))\n"))
        try await expect("FX_IDENTITY_UNVERIFIED", config: fixture("launch_identity_error", prefix + "print(json.dumps(dict(protocol=1,request_id=r['request_id'],ok=False,error=dict(code='FX_IDENTITY_UNVERIFIED',message='blocked',details=dict(stage='CheckingCompatibility')))))\n"), method: "launch_game")
        try await expect("FX_INSTANCE_MISMATCH", config: fixture("launch_foreign_error", prefix + "print(json.dumps(dict(protocol=1,request_id=r['request_id'],ok=False,error=dict(code='FX_INSTANCE_MISMATCH',message='blocked',details=dict(stage='CheckingFXEntry')))))\n"), method: "launch_game")
        try await expect("OUTPUT_LIMIT", config: fixture("stdout_flood", "import sys\nsys.stdout.write('x'*100000)\nsys.stdout.flush()\n"))
        try await expect("OUTPUT_LIMIT", config: fixture("stderr_flood", "import sys\nsys.stderr.write('x'*100000)\nsys.stderr.flush()\n"))
        try await expect("CONFIRMATION_REQUIRED", config: real, method: "launch_game")
        try await expect("PYTHON_UNAVAILABLE", config: BridgeConfiguration(python: directory.appendingPathComponent("missing"), script: script))
        let slow = try fixture("cancellation", "import time\ntime.sleep(10)\n")
        let service = BridgeService()
        let task = Task { try await service.request("get_system_info", configuration: slow) }
        try await Task.sleep(nanoseconds: 100_000_000)
        do { _ = try await service.request("get_system_info", configuration: real); throw ErrorState("EXPECTED_BUSY") }
        catch let error as ErrorState { try check(error.code == "BUSY", "duplicate concurrent request rejected") }
        task.cancel()
        do { _ = try await task.value; throw ErrorState("EXPECTED_CANCELLED") }
        catch let error as ErrorState { try check(error.code == "CANCELLED", "cancellation propagated and worker reaped") }
        let recovered = try await service.request("get_system_info", configuration: real)
        try check(recovered.result["arch"]?.text == "arm64", "service recovers after cancellation")
        let serialized = try await TaskManagerChecks.run()
        try check(serialized, "TaskManager coalesces duplicate refreshes and releases busy")
        print("\(passed) service checks PASS")
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events = 0
    func record(_ event: [String: JSONValue]) { lock.lock(); events += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return events }
}

@MainActor enum TaskManagerChecks {
    static func run() async throws -> Bool {
        let manager = TaskManager()
        var count = 0
        let first = manager.start { count += 1; try? await Task.sleep(nanoseconds: 30_000_000) }
        let duplicate = manager.start { count += 100 }
        while manager.busy { try await Task.sleep(nanoseconds: 10_000_000) }
        return first && !duplicate && count == 1 && !manager.busy
    }
}
