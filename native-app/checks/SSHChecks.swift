import Foundation
import Darwin

@main struct SSHChecks {
    static func main() throws {
        if CommandLine.arguments.contains("--tty-child") {
            let fd = open("/dev/tty", O_RDWR | O_NOCTTY)
            guard fd >= 0 else { exit(41) }
            var terminal = termios()
            guard tcgetattr(fd, &terminal) == 0 else { exit(42) }
            terminal.c_lflag &= ~tcflag_t(ECHO | ECHONL)
            _ = tcsetattr(fd, TCSANOW, &terminal)
            let prompt = Array("Password:".utf8)
            _ = prompt.withUnsafeBytes { write(fd, $0.baseAddress, prompt.count) }
            var bytes = [UInt8](repeating: 0, count: 128)
            let count = read(fd, &bytes, bytes.count)
            let good = String(decoding: bytes.prefix(max(0, count)), as: UTF8.self) == "fixture-secret\n"
            close(fd)
            print(good ? "TTY_AUTH_OK" : "TTY_AUTH_FAILED")
            exit(good ? 0 : 43)
        }
        var failures = 0, passes = 0
        func check(_ value: Bool, _ name: String) {
            if value { passes += 1; print("PASS \(name)") }
            else { failures += 1; print("FAIL \(name)") }
        }
        let transport = SSHTransport.make(["ssh": .object(["host": .string("127.0.0.1"),
            "port": .number(2222), "username": .string("steamos"), "auth": .string("password")])])
        check(transport.commandPrefix.first == "-S", "argv begins with option, never duplicate executable")
        let command = SSHTransport.interactiveCommand(transport.commandPrefix)
        check(command.1.filter { $0 == "/usr/bin/ssh" }.count == 1, "exactly one OpenSSH executable")
        check(command.1.contains("StrictHostKeyChecking=accept-new"), "host identity checking retained")
        check(transport.settings.port == 2222 && transport.settings.username == "steamos", "effective configured endpoint")
        let cases = [("Connection refused", "SSH_CONNECTION_REFUSED"),
                     ("Operation timed out", "SSH_CONNECTION_TIMEOUT"),
                     ("Permission denied", "SSH_AUTH_FAILED"),
                     ("REMOTE HOST IDENTIFICATION HAS CHANGED!", "SSH_HOST_KEY_MISMATCH"),
                     ("Host key verification failed", "SSH_HOST_KEY_MISMATCH"),
                     ("bind: Address already in use", "SSH_LOCAL_PORT_BUSY"),
                     ("Could not resolve hostname", "SSH_CONNECTION_UNREACHABLE"),
                     ("kex_exchange_identification: closed", "SSH_PROTOCOL_ERROR")]
        for (text, code) in cases { check(SSHTransport.failureCode(text) == code, code) }
        check(SSHTransport.failureCode("", timedOut: true) == "SSH_CONNECTION_TIMEOUT", "deadline classification")
        check(transport.sudoVerifyArgs().last == "LC_ALL=C sudo -S -p '' -v", "remote shell preserves empty sudo prompt")
        let sudoCases: [(Int32, String, Bool, String)] = [
            (1, "sudo: a password is required", false, "AUTH_REQUIRED"),
            (1, "sudo: no password was provided", false, "AUTH_REQUIRED"),
            (1, "Sorry, try again.", false, "SUDO_AUTH_FAILED"),
            (1, "not in the sudoers file", false, "SUDO_PERMISSION_DENIED"),
            (1, "usage: sudo -v", false, "SUDO_COMMAND_FAILED"),
            (255, "Connection refused", false, "SSH_CONNECTION_REFUSED"),
            (-1, "", true, "SSH_CONNECTION_TIMEOUT"),
            (1, "unexpected remote failure", false, "SUDO_COMMAND_FAILED")]
        for (status, stderr, timedOut, expected) in sudoCases {
            check(LaunchService.sudoFailure(CoreProcessResult(status: status, stdout: "", stderr: stderr, timedOut: timedOut)) == expected, "sudo distinguishes \(expected)")
        }
        // Run the same native controlling-terminal wrapper against a synthetic password
        // challenge. No real Guest, password, known_hosts or SSH server is used.
        let child = SSHTransport.interactiveCommand(["--tty-child"], executable: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: child.0); process.arguments = child.1
        var master: Int32 = 0, slave: Int32 = 0
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { fatalError("fixture PTY") }
        var term = termios(); _ = tcgetattr(slave, &term); term.c_lflag &= ~tcflag_t(ECHO | ECHONL); _ = tcsetattr(slave, TCSANOW, &term)
        let handle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        process.standardInput = handle; process.standardOutput = handle; process.standardError = handle
        try process.run(); close(slave)
        var output = Data(); var sent = false
        let deadline = CoreClock.monotonic + 5
        while CoreClock.monotonic < deadline {
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            if poll(&descriptor, 1, 100) > 0 && descriptor.revents & Int16(POLLIN) != 0 {
                var chunk = [UInt8](repeating: 0, count: 4096)
                let n = read(master, &chunk, chunk.count)
                if n > 0 { output.append(contentsOf: chunk.prefix(n)) }
            }
            if !sent && String(decoding: output, as: UTF8.self).contains("Password:") {
                let payload = Array("fixture-secret\n".utf8)
                _ = payload.withUnsafeBytes { write(master, $0.baseAddress, payload.count) }; sent = true
            }
            if !process.isRunning { break }
        }
        if process.isRunning { process.terminate() }
        process.waitUntilExit(); close(master)
        let text = String(decoding: output, as: UTF8.self)
        check(sent && text.contains("TTY_AUTH_OK") && process.terminationStatus == 0, "GUI-style PTY opens controlling tty and answers password")
        check(!text.contains("fixture-secret"), "synthetic password never echoed")
        // Exercise the production transport against a deliberately closed local fixture port.
        let closed = socket(AF_INET, SOCK_STREAM, 0)
        var address = sockaddr_in(); address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1")
        _ = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(closed, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(closed, $0, &length) } }
        close(closed)
        let refusal = SSHTransport.make(["ssh": .object(["port": .number(Double(UInt16(bigEndian: address.sin_port)))])])
        do { try refusal.connectOnce(forwarding: false); check(false, "closed port rejected") }
        catch let error as CoreError { check(error.code == "SSH_CONNECTION_REFUSED", "production transport closed port classification [\(error.code)]") }
        check(!transport.passwordWasSent, "cached or absent authentication never proves password")
        print("SSH checks: \(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
