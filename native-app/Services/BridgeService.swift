import Foundation
import Darwin

// Cancellation crosses the detached blocking-I/O worker boundary explicitly.
final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func cancel() { lock.lock(); value = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// Tracks owned workers during AppKit's nested termination loop, independent of MainActor resumption.
enum BridgeWorkerStatus {
    private static let lock = NSLock()
    private static var count = 0
    static func enter() { lock.lock(); count += 1; lock.unlock() }
    static func leave() { lock.lock(); count -= 1; lock.unlock() }
    static var isActive: Bool { lock.lock(); defer { lock.unlock() }; return count > 0 }
}

struct BridgeConfiguration: Sendable {
    let python: URL
    let script: URL
    static func bundled(python: URL) throws -> Self {
        guard let resources = Bundle.main.resourceURL,
              FileManager.default.fileExists(atPath: resources.appendingPathComponent("bridge/bridge.py").path)
        else { throw ErrorState("CORE_UNAVAILABLE") }
        return Self(python: python, script: resources.appendingPathComponent("bridge/bridge.py"))
    }
}

actor BridgeService {
    private var inFlight = false
    func request(_ method: String, configuration: BridgeConfiguration, timeout: TimeInterval = 5, params: [String: JSONValue] = [:], onEvent: (@Sendable ([String: JSONValue]) -> Void)? = nil) async throws -> BridgeReply {
        guard !inFlight else { throw ErrorState("BUSY", method: method) }
        inFlight = true
        defer { inFlight = false }
        let flag = CancellationFlag()
        return try await withTaskCancellationHandler {
            if Task.isCancelled { throw ErrorState("CANCELLED", method: method) }
            return try await Task.detached(priority: .userInitiated) {
                try Self.perform(method, configuration: configuration, timeout: timeout, flag: flag, params: params, onEvent: onEvent)
            }.value
        } onCancel: { flag.cancel() }
    }

    private nonisolated static func perform(_ method: String, configuration: BridgeConfiguration,
                                            timeout: TimeInterval, flag: CancellationFlag, params: [String: JSONValue], onEvent: (@Sendable ([String: JSONValue]) -> Void)?) throws -> BridgeReply {
        let rid = UUID().uuidString
        let redactor = CredentialRedactor(secrets: ["password","passphrase","sudo_password"].compactMap { params[$0]?.text })
        let process = Process()
        process.executableURL = configuration.python
        process.arguments = ["-I", "-B", configuration.script.path]
        // Do not inherit injection variables, credentials or Terminal runtime settings.
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        process.currentDirectoryURL = configuration.script.deletingLastPathComponent()
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = errors
        var handles = [input.fileHandleForWriting, output.fileHandleForReading, errors.fileHandleForReading]
        defer { for handle in handles { try? handle.close() } }
        guard FileManager.default.isExecutableFile(atPath: configuration.python.path) else { throw ErrorState("PYTHON_UNAVAILABLE", method: method) }
        do { try process.run() } catch { throw ErrorState("PYTHON_UNAVAILABLE", method: method) }
        BridgeWorkerStatus.enter()
        defer {
            defer { BridgeWorkerStatus.leave() }
            if process.isRunning {
                process.terminate()
                let grace = ProcessInfo.processInfo.systemUptime + (timeout > 5 ? 10 : 0.2)
                while process.isRunning && ProcessInfo.processInfo.systemUptime < grace { Thread.sleep(forTimeInterval: 0.01) }
                if process.isRunning { Darwin.kill(-process.processIdentifier, SIGKILL); Darwin.kill(process.processIdentifier, SIGKILL) }
            }
            process.waitUntilExit()
        }
        let encoded = try JSONEncoder().encode(params)
        let wireParams = try JSONSerialization.jsonObject(with: encoded)
        let budget = timeout > 5 ? min(900000, Int((timeout - 1) * 1000)) : 3000
        let request: [String: Any] = ["protocol": 1, "request_id": rid, "method": method, "params": wireParams, "timeout_ms": budget]
        let payload = try JSONSerialization.data(withJSONObject: request) + Data([10])
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try input.fileHandleForWriting.write(contentsOf: payload) } catch { throw ErrorState("BRIDGE_EXITED", method: method) }
        try? input.fileHandleForWriting.close()
        handles.removeFirst()
        for h in handles {
            let flags = fcntl(h.fileDescriptor, F_GETFL)
            guard flags >= 0, fcntl(h.fileDescriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw ErrorState("PROTOCOL_ERROR", method: method) }
        }
        var stdout = Data(), stderr = Data()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.02, timeout)
        var eventCount = 0
        func consumeEvents() throws {
            while let newline = stdout.firstIndex(of: 10) {
                let line = Data(stdout[...newline])
                guard let envelope = try? JSONDecoder().decode([String: JSONValue].self, from: line), envelope["event"] != nil else { return }
                guard envelope["request_id"]?.text == rid, envelope["protocol"]?.integer == 1, eventCount < 500 else { throw ErrorState("PROTOCOL_ERROR", method: method) }
                eventCount += 1
                onEvent?(redactor.event(envelope["event"]?.object ?? [:]))
                stdout.removeSubrange(...newline)
            }
        }
        while true {
            if flag.cancelled { throw ErrorState("CANCELLED", method: method) }
            if ProcessInfo.processInfo.systemUptime >= deadline { throw ErrorState("TIMEOUT", method: method) }
            try drain(output.fileHandleForReading.fileDescriptor, into: &stdout, limit: 65_536, method: method)
            try drain(errors.fileHandleForReading.fileDescriptor, into: &stderr, limit: 32_768, method: method)
            try consumeEvents()
            if !process.isRunning {
                try drain(output.fileHandleForReading.fileDescriptor, into: &stdout, limit: 65_536, method: method)
                try drain(errors.fileHandleForReading.fileDescriptor, into: &stderr, limit: 32_768, method: method)
                break
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        try consumeEvents()
        guard process.terminationStatus == 0 else { throw ErrorState("BRIDGE_EXITED", method: method, details: ["exit_code": .number(Double(process.terminationStatus))]) }
        // One request per supervised process: require exactly one complete UTF-8 frame.
        guard stdout.last == 10, let string = String(data: stdout, encoding: .utf8),
              string.dropLast().contains("\n") == false,
              let response = try? JSONDecoder().decode(BridgeResponse.self, from: stdout), response.request_id == rid
        else { throw ErrorState("PROTOCOL_ERROR", method: method) }
        guard response.protocol == 1 else { throw ErrorState("PROTOCOL_MISMATCH", method: method) }
        if !response.ok {
            guard response.result == nil, let failure = response.error else { throw ErrorState("PROTOCOL_ERROR", method: method) }
            let codes = ["TIMEOUT", "CORE_UNAVAILABLE", "NOT_IMPLEMENTED", "PROTOCOL_ERROR", "PROTOCOL_MISMATCH", "INVALID_ARGUMENT", "OUTPUT_LIMIT"]
            let operationCodes = ["CONFIRMATION_REQUIRED", "CHANGE_CONFIRMATION_REQUIRED", "CONFIG_CHANGED", "AUTH_REQUIRED", "SOURCE_MISMATCH", "RUNTIME_ROOT_REQUIRED", "UNSAFE_PATH", "CANCELLED", "UNSUPPORTED_CONFIGURATION", "PROFILE_NOT_APPLICABLE"]
            let launchCodes = ["LAUNCHER_FILES_MISSING", "FX_UNAVAILABLE", "GVPROXY_UNAVAILABLE", "NODE_UNAVAILABLE", "SSH_UNAVAILABLE", "FX_PROFILE_MISMATCH", "ENVIRONMENT_CHECK_FAILED", "FX_START_FAILED", "SSH_CONNECTION_FAILED", "COMPATIBILITY_CHECK_FAILED", "STEAM_START_FAILED", "GAME_START_FAILED", "GAME_EXITED", "EAC_CHECK_FAILED", "LAUNCH_FAILED", "FX_IDENTITY_UNVERIFIED", "FX_INSTANCE_MISMATCH", "FX_ENTRY_MISMATCH"]
            let credentialCodes = ["CREDENTIAL_SCOPE_CHANGED", "SENSITIVE_CONFIGURATION", "SENSITIVE_CHANGE_BLOCKED", "SSH_AUTH_FAILED", "SUDO_AUTH_FAILED", "GUEST_TRANSACTION_FAILED"]
            let guiCodes = ["FX_NOT_RUNNING", "LOCAL_FX_REQUIRED", "GUEST_INSPECTION_FAILED"]
            throw ErrorState((codes + operationCodes + launchCodes + credentialCodes + guiCodes).contains(failure.code) ? failure.code : "PROTOCOL_ERROR", method: method, details: redactor.diagnostic(failure.details ?? [:]))
        }
        guard let result = response.result, response.error == nil,
              let observed = response.observed_at, !observed.isEmpty else { throw ErrorState("PROTOCOL_ERROR", method: method) }
        if method == "handshake" {
            guard result["protocol_min"]?.integer == 1, result["protocol_max"]?.integer == 1,
                  (result["read_only"]?.boolean == true || (result["permission_model"]?.text == "explicit_actions" && result["read_only_default"]?.boolean == true)),
                  Set(result["capabilities"]?.array.compactMap(\.text) ?? []).isSuperset(of: ["get_launcher_version", "get_system_info", "get_environment_status", "get_dependencies", "list_fx_versions", "get_logs"])
            else { throw ErrorState("PROTOCOL_MISMATCH", method: method) }
        }
        return BridgeReply(result: result, observedAt: observed, requestID: rid)
    }

    private nonisolated static func drain(_ fd: Int32, into data: inout Data, limit: Int, method: String) throws {
        var bytes = [UInt8](repeating: 0, count: 4096)
        // Bounded per iteration so a flood cannot starve deadline/cancellation checks.
        for _ in 0..<20 {
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 { return }
            if count < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { return }
                if errno == EINTR { continue }
                throw ErrorState("PROTOCOL_ERROR", method: method)
            }
            guard data.count + count <= limit else { throw ErrorState("OUTPUT_LIMIT", method: method) }
            data.append(contentsOf: bytes.prefix(count))
        }
    }
}
