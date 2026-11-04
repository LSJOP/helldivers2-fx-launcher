import Foundation
import Darwin

/// Controlled OpenSSH transport. Secrets reach ssh only through the allocated PTY,
/// never argv, environment, files or logs.
final class SSHTransport {
    struct Settings: Sendable, Equatable {
        var host: String
        var port: Int
        var username: String
        var auth: String
        var identityFile: String
        var cdpLocalPort: Int
        var rememberPassword: Bool
        var socketPath: String
    }

    let settings: Settings
    private(set) var passwordWasSent = false
    private(set) var password: String?
    private(set) var passphrase: String?

    init(settings: Settings) {
        self.settings = settings
    }

    static func make(_ configuration: [String: JSONValue]) -> SSHTransport {
        let ssh = configuration["ssh"]?.object ?? [:]
        let host = ssh["host"]?.text ?? "127.0.0.1"
        let port = ssh["port"]?.integer ?? 2222
        let username = ssh["username"]?.text ?? "steamos"
        let cdp = ssh["cdp_local_port"]?.integer ?? 18094
        let encoded = CoreJSON.encode(.object(["branch": .number(2), "host": .string(host),
                                               "port": .number(Double(port)), "user": .string(username),
                                               "cdp": .number(Double(cdp))]))
        let suffix = String(CoreHash.sha256(Data(encoded.utf8)).prefix(14))
        return SSHTransport(settings: Settings(host: host, port: port, username: username,
                                              auth: ssh["auth"]?.text ?? "password",
                                              identityFile: ssh["identity_file"]?.text ?? "",
                                              cdpLocalPort: cdp,
                                              rememberPassword: false,
                                              socketPath: "/tmp/hd2fx-\(getuid())-\(suffix).sock"))
    }

    /// Setup/sudo checks own a fresh master and never alter/reuse the launch CDP tunnel.
    static func isolatedSetup(_ configuration: [String: JSONValue]) -> SSHTransport {
        var settings = make(configuration).settings
        settings.socketPath = "/tmp/hd2fx-setup-\(getuid())-\(UUID().uuidString).sock"
        return SSHTransport(settings: settings)
    }

    static func localHost(_ host: String) -> Bool {
        ["127.0.0.1", "localhost", "::1"].contains(host)
    }

    var commandPrefix: [String] {
        ["-S", settings.socketPath, "-p", String(settings.port), "-l", settings.username,
         "-o", "ConnectTimeout=8", "-o", "StrictHostKeyChecking=accept-new",
         "-o", "NumberOfPasswordPrompts=1"]
    }

    private var authArguments: [String] {
        if settings.auth == "key" {
            var args = ["-o", "PreferredAuthentications=publickey"]
            if !settings.identityFile.isEmpty {
                args += ["-i", (settings.identityFile as NSString).expandingTildeInPath, "-o", "IdentitiesOnly=yes"]
            }
            return args
        }
        return ["-o", "PreferredAuthentications=password,keyboard-interactive"]
    }

    func reachable(timeout: TimeInterval = 0.7) -> Bool {
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(settings.port).bigEndian)
        if inet_pton(AF_INET, settings.host, &address.sin_addr) != 1 {
            // Hostnames resolve through the system resolver.
            guard let host = gethostbyname(settings.host), let first = host.pointee.h_addr_list?[0] else { return false }
            memcpy(&address.sin_addr, UnsafeRawPointer(first), Int(host.pointee.h_length))
        }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// Returns the master pid when an authenticated multiplexed connection already exists.
    func masterPID(context: CoreContext? = nil) -> Int? {
        guard let result = try? CoreProcess.run("/usr/bin/ssh",
                                                 ["-S", settings.socketPath, "-O", "check", settings.host],
                                                 timeout: 8, context: context) else { return nil }
        let text = result.stderr + result.stdout
        guard let match = text.range(of: #"Master running \(pid=(\d+)\)"#, options: .regularExpression) else { return nil }
        let digits = text[match].filter(\.isNumber)
        return Int(digits)
    }

    /// macOS script uses forkpty/login_tty. Process + openpty alone does not
    /// supply /dev/tty to OpenSSH when launched from Finder/LaunchServices.
    static func interactiveCommand(_ arguments: [String], executable: String = "/usr/bin/ssh") -> (String, [String]) {
        ("/usr/bin/script", ["-q", "/dev/null", executable] + arguments)
    }

    static func failureCode(_ output: String, timedOut: Bool = false) -> String {
        let text = output.lowercased()
        if text.contains("host identification has changed") || text.contains("host key verification failed") { return "SSH_HOST_KEY_MISMATCH" }
        if text.contains("address already in use") || text.contains("cannot listen to port") { return "SSH_LOCAL_PORT_BUSY" }
        if text.contains("connection refused") { return "SSH_CONNECTION_REFUSED" }
        if timedOut || text.contains("connection timed out") || text.contains("operation timed out") { return "SSH_CONNECTION_TIMEOUT" }
        if text.contains("permission denied") || text.contains("authentication failed") { return "SSH_AUTH_FAILED" }
        if text.contains("could not resolve hostname") || text.contains("no route to host") { return "SSH_CONNECTION_UNREACHABLE" }
        return "SSH_PROTOCOL_ERROR"
    }

    func connectOnce(context: CoreContext? = nil, forwarding: Bool = true) throws {
        if masterPID(context: context) != nil { return }
        var arguments = commandPrefix + authArguments
        arguments += ["-M", "-N", "-f", "-o", "ControlMaster=yes", "-o", "ExitOnForwardFailure=yes",
                      "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=3"]
        arguments += forwarding ? ["-L", "127.0.0.1:\(settings.cdpLocalPort):127.0.0.1:8080"] : ["-o", "ClearAllForwardings=yes"]
        arguments.append(settings.host)
        let process = Process()
        let command = Self.interactiveCommand(arguments)
        process.executableURL = URL(fileURLWithPath: command.0)
        process.arguments = command.1
        process.environment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin", "LANG": "en_US.UTF-8"]
        var masterFD: Int32 = 0, slaveFD: Int32 = 0
        var size = winsize(ws_row: 40, ws_col: 120, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&masterFD, &slaveFD, nil, nil, &size) == 0 else { throw CoreError("SSH_UNAVAILABLE") }
        var terminal = termios()
        if tcgetattr(slaveFD, &terminal) == 0 {
            terminal.c_lflag &= ~tcflag_t(ECHO | ECHONL)
            _ = tcsetattr(slaveFD, TCSANOW, &terminal)
        }
        let slave = FileHandle(fileDescriptor: slaveFD, closeOnDealloc: false)
        process.standardInput = slave
        process.standardOutput = slave
        process.standardError = slave
        do { try process.run() } catch { close(masterFD); close(slaveFD); throw CoreError("SSH_UNAVAILABLE") }
        close(slaveFD)
        defer { close(masterFD) }
        let deadline = min(context?.deadline ?? .greatestFiniteMagnitude, CoreClock.monotonic + 25)
        var buffer = Data()
        var sent = false
        var exited = false
        // All early exits close the PTY, terminating the script-owned SSH session.
        defer {
            if process.isRunning { process.terminate() }
        }
        while CoreClock.monotonic < deadline {
            if context?.isCancelled == true { process.terminate(); throw CoreError("CANCELLED") }
            var descriptor = pollfd(fd: masterFD, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 150)
            if ready > 0, (descriptor.revents & Int16(POLLIN)) != 0 {
                var chunk = [UInt8](repeating: 0, count: 4096)
                let count = read(masterFD, &chunk, chunk.count)
                if count > 0 {
                    buffer.append(contentsOf: chunk.prefix(count))
                    if buffer.count > 8192 { buffer = buffer.suffix(8192) }
                }
            }
            if !process.isRunning { exited = true; break }
            let text = String(decoding: buffer, as: UTF8.self).lowercased()
            if !sent, text.contains("password" + ":"), !text.contains("passphrase for key") {
                guard let value = password else {
                    process.terminate()
                    throw CoreError("AUTH_REQUIRED", ["credential_kind": .string("password")])
                }
                guard !value.contains("\n"), !value.contains("\r") else {
                    process.terminate(); throw CoreError("SSH_AUTH_FAILED")
                }
                let payload = Array((value + "\n").utf8)
                _ = payload.withUnsafeBytes { write(masterFD, $0.baseAddress, payload.count) }
                sent = true
                passwordWasSent = true
            } else if !sent, text.contains("passphrase for key") {
                guard let value = passphrase else {
                    process.terminate()
                    throw CoreError("AUTH_REQUIRED", ["credential_kind": .string("passphrase")])
                }
                guard !value.contains("\n"), !value.contains("\r") else {
                    process.terminate(); throw CoreError("SSH_AUTH_FAILED")
                }
                let payload = Array((value + "\n").utf8)
                _ = payload.withUnsafeBytes { write(masterFD, $0.baseAddress, payload.count) }
                sent = true
            }
        }
        if !exited {
            process.terminate()
            let grace = CoreClock.monotonic + 1
            while process.isRunning && CoreClock.monotonic < grace { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw CoreError(Self.failureCode(String(decoding: buffer, as: UTF8.self), timedOut: true))
        }
        process.waitUntilExit()
        let text = String(decoding: buffer, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let code = Self.failureCode(text)
            if code == "SSH_AUTH_FAILED" { password = nil; passphrase = nil }
            throw CoreError(code)
        }
        guard masterPID(context: context) != nil else { throw CoreError("SSH_PROTOCOL_ERROR") }
    }

    func setSecret(password: String?, passphrase: String?) {
        if let password { self.password = password }
        if let passphrase { self.passphrase = passphrase }
    }

    /// Runs a command through the existing master with BatchMode (never prompts).
    func run(_ script: String, timeout: TimeInterval = 30, context: CoreContext? = nil) throws -> CoreProcessResult {
        var arguments = ["-S", settings.socketPath, "-p", String(settings.port), "-l", settings.username,
                         "-o", "BatchMode=yes", "-o", "ConnectTimeout=8", settings.host, "sh", "-s"]
        let result = try CoreProcess.run("/usr/bin/ssh", arguments, input: script, timeout: timeout, context: context)
        if result.timedOut { throw CoreError("TIMEOUT") }
        if result.status == 255 { throw CoreError(Self.failureCode(result.stderr)) }
        return result
    }

    func closeMaster() {
        _ = try? CoreProcess.run("/usr/bin/ssh", ["-S", settings.socketPath, "-O", "exit", settings.host], timeout: 8)
    }
}
