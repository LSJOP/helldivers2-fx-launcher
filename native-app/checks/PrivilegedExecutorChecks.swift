import Foundation
import Darwin

@main struct PrivilegedExecutorChecks {
 static func main() throws {
    var passed = 0
    func check(_ value: Bool, _ name: String) {
        guard value else { print("FAIL " + name); exit(1) }
        passed += 1; print("PASS " + name)
    }
    func expect(_ code: String, _ name: String, _ body: () throws -> Void) {
        do { try body(); check(false, name) }
        catch let error as CoreError { check(error.code == code, name + " [" + error.code + "]") }
        catch { check(false, name + " unexpected error") }
    }
    let t = SSHTransport.make([:]); let secret = "fixture-only-password"
    let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hd2-sudo-fixture-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let fakeSudo = root.appendingPathComponent("sudo")
    let fakeID = root.appendingPathComponent("id")
    let sudoScript = """
    #!/bin/sh
    fresh=false; prompt=''; mode=''
    while [ "$#" -gt 0 ]; do
      case "$1" in -k) fresh=true; shift;; -S) mode=password; shift;; -n) mode=noninteractive; shift;; -p) prompt=$2; shift 2;; --) shift; break;; *) exit 91;; esac
    done
    [ "$mode" = password ] && [ "$fresh" = true ] || { printf 'sudo: a password is required\\n' >&2; exit 1; }
    printf '%s' "$prompt" >&2
    IFS= read -r supplied || { printf 'sudo: no password was provided\\n' >&2; exit 1; }
    [ "$supplied" = 'fixture-only-password' ] || { printf 'Sorry, try again.\\n' >&2; exit 1; }
    exec "$@"
    """
    try Data(sudoScript.utf8).write(to: fakeSudo)
    // The approved command must observe EOF, not the authentication bytes.
    try Data("#!/bin/sh\nif IFS= read -r unexpected; then printf 'INPUT_LEAK\\n'; exit 9; fi\nprintf '0\\n'\n".utf8).write(to: fakeID)
    for file in [fakeSudo, fakeID] { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path) }
    var calls = 0
    let runner: ([String], String?, CoreContext) throws -> CoreProcessResult = { args, input, context in
        calls += 1
        check(!args.joined(separator: " ").contains(secret), "password absent from SSH argv")
        let remote = args.last!.replacingOccurrences(of: "LC_ALL=C sudo ", with: "LC_ALL=C " + GuestPrivilegedExecutor.quote(fakeSudo.path) + " ")
        return try CoreProcess.run("/bin/sh", ["-c", remote], input: input, timeout: 3,
            environment: ["PATH": root.path + ":/usr/bin:/bin"], context: context)
    }
    for _ in 0..<3 {
        let result = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: {}, process: runner)
        check(result["password_verified"]?.boolean == true && result["cache_dependency"]?.boolean == false, "independent authentication and command with no cache")
    }
    check(calls == 3, "multiple calls each execute authentication")
    expect("SUDO_AUTH_FAILED", "wrong sudo password not retried") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: "fixture-wrong", context: CoreContext(timeout: 5), verifyTarget: {}, process: runner)
    }
    expect("AUTH_REQUIRED", "missing sudo credential distinct") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: nil, context: CoreContext(timeout: 5), verifyTarget: {}, process: runner)
    }
    let prior = calls
    expect("FX_ENTRY_MISMATCH", "identity mismatch prevents transmission") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: { throw CoreError("FX_ENTRY_MISMATCH") }, process: runner)
    }
    check(calls == prior, "no process after failed identity")
    expect("SUDO_CREDENTIAL_INVALID", "multiline credential rejected") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: "fixture-invalid\nextra", context: CoreContext(timeout: 5), verifyTarget: {}, process: runner)
    }
    let cancelled = CoreContext(timeout: 5); cancelled.cancel()
    expect("CANCELLED", "cancel before send") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: cancelled, verifyTarget: {}, process: runner)
    }
    expect("CANCELLED", "cancelled command cannot report authenticated success") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: {}, process: { _,_,context in
            context.cancel(); return CoreProcessResult(status: 0, stdout: "0", stderr: GuestPrivilegedExecutor.challenge, timedOut: false)
        })
    }
    expect("CONFIRMATION_REQUIRED", "Guest write requires exact caller approval") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .ipv6(boot: UUID().uuidString, values: [:]), password: secret, context: CoreContext(timeout: 5), verifyTarget: {}, process: runner)
    }
    expect("INVALID_ARGUMENT", "untrusted operation parameters rejected") {
        _ = try GuestPrivilegedExecutor.arguments(t, operation: .ipv6(boot: "injected'; exit 0", values: [:]), hasPassword: true)
    }
    let cases: [(Int32, String, Bool, String)] = [(255, "Connection refused", false, "SSH_CONNECTION_REFUSED"),
        (1, "not in the sudoers file", false, "SUDO_PERMISSION_DENIED"), (1, "usage: sudo", false, "SUDO_COMMAND_FAILED"),
        (-1, "", true, "SSH_CONNECTION_TIMEOUT")]
    for (status, stderr, timedOut, code) in cases {
        expect(code, "structured failure " + code) {
            _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: {}, process: { _,_,_ in
                CoreProcessResult(status: status, stdout: "", stderr: stderr, timedOut: timedOut)
            })
        }
    }
    expect("SUDO_COMMAND_FAILED", "non-root stdout cannot establish privilege") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: {}, process: { _,_,_ in
            CoreProcessResult(status: 0, stdout: "1000", stderr: GuestPrivilegedExecutor.challenge, timedOut: false)
        })
    }
    var checks = 0
    expect("FX_ENTRY_MISMATCH", "identity changes during command invalidate result") {
        _ = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: {
            checks += 1; if checks == 2 { throw CoreError("FX_ENTRY_MISMATCH") }
        }, process: runner)
    }
    let unprompted = try GuestPrivilegedExecutor.run(t, operation: .verify, password: secret, context: CoreContext(timeout: 5), verifyTarget: {}, process: { _,_,_ in
        CoreProcessResult(status: 0, stdout: "0", stderr: "", timedOut: false)
    })
    check(unprompted["password_verified"]?.boolean == false, "NOPASSWD/cached success never proves password")
    let quoted = "a'b c\n$HOME;`echo bad`"
    let quoteProbe = try CoreProcess.run("/bin/sh", ["-c", "printf '%s' " + GuestPrivilegedExecutor.quote(quoted)])
    check(quoteProbe.stdout == quoted, "remote script shell quoting is lossless")
    check(!(try GuestPrivilegedExecutor.script(.verify)).contains(secret), "target script contains no password")
    check(!GuestService.steamReady(["steam_logged_on": .bool(true), "steam_count": .number(0), "service": .string("stopped")]), "historical login cannot establish Steam readiness")
    check(GuestService.steamReady(["steam_logged_on": .bool(true), "steam_count": .number(1), "service": .string("running")]), "Steam readiness requires current process and service")
    print("\(passed) privileged executor checks PASS (isolated fixtures; no Guest changes)")
 }
}
