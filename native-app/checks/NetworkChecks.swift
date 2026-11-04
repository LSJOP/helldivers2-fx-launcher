import Foundation
@main struct NetworkChecks {
 static var count = 0
 static func check(_ condition: Bool, _ name: String) { if !condition { fatalError("FAIL " + name) }; count += 1; print("PASS " + name) }
 static func expect(_ code: String, _ name: String, _ body: () throws -> Void) {
  do { try body(); fatalError("FAIL " + name) } catch let e as CoreError { check(e.code == code, name + " [" + e.code + "]") } catch { fatalError("unexpected \(error)") }
 }
 static func main() throws {
  let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("hd2-network-fixture-" + UUID().uuidString)
  setenv("HD2FX_NATIVE_TEST_ROOT", root.path, 1); defer { try? FileManager.default.removeItem(at: root) }
  let boot = UUID().uuidString
  let initial = ["all":"0", "default":"0", "eth0":"0", "lo":"0", "veth-test":"1"]
  var current = GuestIPv6Snapshot(boot: boot, values: initial)
  check(current.status == "enabled", "four controls enabled, other interface preserved")
  check(GuestIPv6Snapshot(boot: boot, values: initial.mapValues { _ in "1" }).status == "disabled", "disabled")
  var mixed = initial; mixed["eth0"] = "1"
  check(GuestIPv6Snapshot(boot: boot, values: mixed).status == "mixed", "mixed not repaired")
  check(GuestIPv6Snapshot(boot: boot, values: [:]).status == "unknown", "missing means unknown")
  check(!GuestIPv6Snapshot.validName("..") && !GuestIPv6Snapshot.validName("eth0/../../"), "interface traversal rejected")
  let t = SSHTransport.make(ConfigurationService.defaults())
  let session = GuestSession(boot: boot, identitySignature: "fixture-target", plan: [:])
  var bound = SteamOSNetworkService.Bound(transport: t, session: session, fx: root, context: CoreContext(timeout: 100))
  bound.identityProbe = { _ in }; bound.readProbe = { _ in current }; bound.idleProbe = { _ in }
  var calls = 0
  let apply: (GuestIPv6Snapshot, [String:String], CoreContext) throws -> Void = { snapshot, values, _ in
   check(snapshot == current, "executor receives compare-and-swap before snapshot"); calls += 1; current = GuestIPv6Snapshot(boot: boot, values: values)
  }
  let plan = try SteamOSNetworkService.preview(bound, enabled: false)
  check(plan["after"]?.object["veth-test"]?.text == "1", "preview preserves nonprimary interfaces")
  expect("CONFIRMATION_REQUIRED", "cancel causes no write") { _ = try SteamOSNetworkService.apply(bound, plan: plan, password: nil, confirmed: false, executor: apply) }
  check(calls == 0, "zero writes after cancellation")
  let done = try SteamOSNetworkService.apply(bound, plan: plan, password: nil, confirmed: true, executor: apply)
  check(current.status == "disabled" && done["status"]?.text == "disabled", "disable plus readback")
  let backup = done["backup_path"]!.text!
  let saved = try SteamOSNetworkService.load(backup)
  check(saved["before"]?.object == initial.mapValues(JSONValue.string), "complete durable prewrite backup")
  let unchanged = try SteamOSNetworkService.preview(bound, enabled: false)
  let previous = calls
  _ = try SteamOSNetworkService.apply(bound, plan: unchanged, password: nil, confirmed: true, executor: apply)
  check(calls == previous, "idempotent no auth or writes")
  var reconnected = bound
  reconnected.stableTarget = "fixture-target"
  check(reconnected.receiptIdentity == bound.receiptIdentity, "same stable target can reuse trusted receipt after SSH reconnect")
  let restore = try SteamOSNetworkService.preview(bound, enabled: nil, backup: backup)
  _ = try SteamOSNetworkService.apply(bound, plan: restore, password: nil, confirmed: true, executor: apply)
  check(current.values == initial, "manual restore exact original values")
  expect("UNTRUSTED_BACKUP", "no trusted snapshot forbids restore") { _ = try SteamOSNetworkService.preview(bound, enabled: nil, backup: root.appendingPathComponent("fake.json").path) }
  let enablePlan = try SteamOSNetworkService.preview(bound, enabled: true)
  check(enablePlan["changed"]?.boolean == false, "enable already enabled is no-op")
  current = GuestIPv6Snapshot(boot: boot, values: initial.mapValues { _ in "1" })
  let enable = try SteamOSNetworkService.preview(bound, enabled: true)
  _ = try SteamOSNetworkService.apply(bound, plan: enable, password: nil, confirmed: true, executor: apply)
  check(current.status == "enabled", "user enables IPv6")
  current = GuestIPv6Snapshot(boot: boot, values: initial)
  let authPlan = try SteamOSNetworkService.preview(bound, enabled: false)
  var rejectedCalls = 0
  expect("SUDO_AUTH_FAILED", "rejected password is never retried as recovery") {
   _ = try SteamOSNetworkService.apply(bound, plan: authPlan, password: "fixture-wrong-synthetic", confirmed: true, executor: { _,_,_ in
    rejectedCalls += 1
    var external = current.values; external["all"] = "1"; current = GuestIPv6Snapshot(boot: boot, values: external)
    throw CoreError("SUDO_AUTH_FAILED")
   })
  }
  check(rejectedCalls == 1, "one authentication attempt despite concurrent external value change")
  current = GuestIPv6Snapshot(boot: boot, values: initial)
  let failurePlan = try SteamOSNetworkService.preview(bound, enabled: false)
  var failures = 0
  let partial: (GuestIPv6Snapshot,[String:String],CoreContext) throws -> Void = { _,values,_ in
   failures += 1
   if failures == 1 { var part = current.values; part["all"] = "1"; current = GuestIPv6Snapshot(boot: boot, values: part); throw CoreError("IPV6_APPLY_FAILED") }
   current = GuestIPv6Snapshot(boot: boot, values: values)
  }
  do { _ = try SteamOSNetworkService.apply(bound, plan: failurePlan, password: nil, confirmed: true, executor: partial); fatalError("must fail") }
  catch let e as CoreError { check(e.details["recovery_status"]?.text == "rolled_back" && current.values == initial, "partial failure automatically restored and verified") }
  var remainingBackup = ""
  do { _ = try SteamOSNetworkService.apply(bound, plan: failurePlan, password: nil, confirmed: true, executor: { _,_,_ in
    var part = current.values; part["all"] = "1"; current = GuestIPv6Snapshot(boot: boot, values: part); throw CoreError("IPV6_APPLY_FAILED")
   }); fatalError("must fail") }
  catch let e as CoreError { remainingBackup = e.details["backup_path"]!.text!; check(e.details["recovery_status"]?.text == "restore_required" && e.details["actual_values"]?.object["all"]?.text == "1", "failed recovery exposes actual residue") }
  let recoverPartial = try SteamOSNetworkService.preview(bound, enabled: nil, backup: remainingBackup)
  _ = try SteamOSNetworkService.apply(bound, plan: recoverPartial, password: nil, confirmed: true, executor: apply)
  check(current.values == initial, "manual recovery from partial application")
  var changed = failurePlan; changed["fx_identity"] = .string("wrong")
  expect("CONFIG_CHANGED", "target mismatch prevents mutation") { _ = try SteamOSNetworkService.apply(bound, plan: changed, password: nil, confirmed: true, executor: apply) }
  bound.identityProbe = { _ in throw CoreError("FX_ENTRY_MISMATCH") }
  expect("FX_ENTRY_MISMATCH", "identity verification required") { _ = try SteamOSNetworkService.preview(bound, enabled: true) }
  bound.identityProbe = { _ in }
  let after = current.desired(enabled: false)
  let script = try GuestPrivilegedExecutor.script(.networkIPv6(boot: boot, before: current.values, after: after))
  check(script.contains("exit 76") && script.contains("veth-test") && script.contains("pgrep"), "production privileged script guards interface drift and active game")
  check(!script.contains("sysctl.d") && !script.contains("sudoers"), "no persistent config or sudo policy edits")
  let syntax = try CoreProcess.run("/bin/sh", ["-n", "-c", script], timeout: 3)
  check(syntax.status == 0, "actual production shell quoting parses")
  let proc = root.appendingPathComponent("proc")
  let bootFile = proc.appendingPathComponent("sys/kernel/random/boot_id")
  try FileManager.default.createDirectory(at: bootFile.deletingLastPathComponent(), withIntermediateDirectories: true)
  try Data((boot + "\n").utf8).write(to: bootFile)
  for (key,value) in current.values {
   let file = proc.appendingPathComponent("sys/net/ipv6/conf/" + key + "/disable_ipv6")
   try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
   try Data((value + "\n").utf8).write(to: file)
  }
  let shim = root.appendingPathComponent("sudo-fixture")
  let synthetic = "fixture-network-secret"
  let shimBody = """
  #!/bin/sh
  while [ "$#" -gt 0 ]; do
    case "$1" in -k|-S) shift;; -p) printf '%s' "$2" >&2; shift 2;; --) shift; break;; *) exit 99;; esac
  done
  IFS= read -r supplied
  [ "$supplied" = 'fixture-network-secret' ] || exit 1
  exec "$@"
  """
  try Data(shimBody.utf8).write(to: shim)
  try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:shim.path)
  let runner: ([String],String?,CoreContext)throws->CoreProcessResult = { args,input,context in
   check(!args.joined().contains(synthetic), "production IPv6 executor keeps secret out of argv")
   let remote = args.last!.replacingOccurrences(of: "LC_ALL=C sudo ", with: "LC_ALL=C " + GuestPrivilegedExecutor.quote(shim.path) + " ").replacingOccurrences(of:"/proc/",with:proc.path + "/")
   return try CoreProcess.run("/bin/sh",["-c",remote],input:input,timeout:3,context:context)
  }
  let actual = try GuestPrivilegedExecutor.run(t, operation:.networkIPv6(boot:boot,before:current.values,after:after), password:synthetic,approved:true,context:CoreContext(timeout:5),verifyTarget:{},process:runner)
  check(actual["password_verified"]?.boolean == true, "actual production IPv6 shell executed through independent auth fixture")
  for (key,value) in after {
   let observed = try String(contentsOf:proc.appendingPathComponent("sys/net/ipv6/conf/" + key + "/disable_ipv6")).trimmingCharacters(in:.whitespacesAndNewlines)
   check(observed == value, "production shell readback " + key)
  }
  expect("CONFIG_CHANGED", "privileged command rechecks old values before writing") {
   _ = try GuestPrivilegedExecutor.run(t,operation:.networkIPv6(boot:boot,before:current.values,after:after),password:synthetic,approved:true,context:CoreContext(timeout:5),verifyTarget:{},process:runner)
  }
  let nonce = Array<UInt8>(0..<12)
  var response = NetworkDiagnosticsService.requestBytes(transaction: nonce); response[0] = 1; response[1] = 1
  check(NetworkDiagnosticsService.validSTUN(Data(response), transaction: nonce), "STUN response transaction matched")
  var wrong = response; wrong[8] = 100
  check(!NetworkDiagnosticsService.validSTUN(Data(wrong), transaction: nonce), "wrong STUN transaction rejected")
  wrong = response; wrong[3] = 8
  check(!NetworkDiagnosticsService.validSTUN(Data(wrong), transaction: nonce), "truncated STUN attributes rejected")
  let curl = NetworkDiagnosticsService.curlArgs(host: "store.steampowered.com", proxy: "http://127.0.0.1:7890")
  check(!curl.contains("--insecure") && curl.contains("--disable") && curl.contains("--max-time"), "TLS certificate checks retained with bounded timeout")
  let tlsPass = CoreProcessResult(status: 0, stdout: "0.025", stderr: "", timedOut: false)
  let tlsFail = CoreProcessResult(status: 60, stdout: "", stderr: "certificate rejected", timedOut: false)
  check(NetworkDiagnosticsService.classifyCurl(tlsPass) == .pass && NetworkDiagnosticsService.classifyCurl(tlsFail) == .fail, "TLS success and certificate failure")
  check(NetworkDiagnosticsService.classifyCurl(CoreProcessResult(status: 28, stdout: "", stderr: "", timedOut: false)) == .timeout, "timeout inconclusive distinct from fail")
  var guestCalls = 0
  let guest: (String,TimeInterval,CoreContext)throws->CoreProcessResult = { script,_,_ in
   guestCalls += 1
   check(!script.contains("sudo") && !script.contains("disable_ipv6") && !script.contains("sysctl -w") && !script.contains("systemctl"), "diagnostic has no configuration mutator")
   if script.contains("pgrep") { return CoreProcessResult(status: 0, stdout: "idle", stderr: "", timedOut: false) }
   if script.contains("curl") { return tlsPass }
   if script.contains("/dev/udp") {
    let octal = script.components(separatedBy: "printf")[1]
    let regex = try NSRegularExpression(pattern: #"\\([0-7]{3})"#)
    let ns = octal as NSString
    let bytes = regex.matches(in: octal, range: NSRange(location: 0, length: ns.length)).compactMap { UInt8(ns.substring(with: $0.range(at: 1)), radix: 8) }
    var reply = Array(bytes.prefix(20)); reply[0] = 1; reply[1] = 1
    return CoreProcessResult(status: 0, stdout: Data(reply).base64EncodedString(), stderr: "", timedOut: false)
   }
   return CoreProcessResult(status: 0, stdout: "InDatagrams=2\nOutDatagrams=3\ngame_sockets=0\nconnected_sockets=0\n", stderr: "", timedOut: false)
  }
  let result = try NetworkDiagnosticsService.run(bound: nil, bindingFailure: nil, context: CoreContext(timeout: 30), emit: { _,_,_ in }, hostProbe: { _,_ in tlsPass }, guestProbe: guest)
  check(result["items"]!.array.allSatisfy { $0.object["status"]?.text == "PASS" }, "all four real probe algorithms with controlled responses")
  check(result["multiplayer"]?.text == "NOT_TESTED", "probe pass never becomes multiplayer pass")
  let paused = try NetworkDiagnosticsService.run(bound: nil, bindingFailure: "SSH_DISCONNECTED", context: CoreContext(timeout: 5), emit: { _,_,_ in })
  check(paused["items"]!.array.allSatisfy { $0.object["status"]?.text == "PAUSED" }, "disconnected Guest pauses without authentication or sudo")
  let cancel = CoreContext(timeout: 5); cancel.cancel()
  expect("CANCELLED", "user cancels diagnosis") { _ = try NetworkDiagnosticsService.run(bound: nil, bindingFailure: nil, context: cancel, emit: { _,_,_ in }) }
  let fail = try NetworkDiagnosticsService.run(bound: nil, bindingFailure: nil, context: CoreContext(timeout: 30), emit: { _,_,_ in }, hostProbe: { _,_ in tlsFail }, guestProbe: { script,_,_ in
   if script.contains("pgrep") { return CoreProcessResult(status: 0, stdout: "idle", stderr: "", timedOut: false) }
   return CoreProcessResult(status: script.contains("curl") ? 60 : 124, stdout: "", stderr: "", timedOut: false)
  })
  check(fail["items"]!.array[1].object["status"]?.text == "FAIL" && fail["items"]!.array[2].object["status"]?.text == "FAIL" && fail["items"]!.array[3].object["status"]?.text == "TIMEOUT", "TLS/PlayFab fail and UDP timeout remain separate")
  let source = try String(contentsOfFile: "Core/NativeCoreService.swift")
  let launch = source.components(separatedBy: "static func launchGame")[1]
  check(!launch.contains("ensureIPv4") && !launch.contains("GuestPrivilegedExecutor") && !launch.contains("GuestScripts.ipv6"), "production launch chain contains no IPv6 writer or sudo")
  let compatible = ["vulkan":JSONValue.bool(true), "tool":.string(LaunchService.verifiedTool), "fex":.string(LaunchService.verifiedFEX), "ntdll":.string(LaunchService.verifiedNTDLL), "wine_core":.object(LaunchService.verifiedWine.mapValues(JSONValue.string))]
  for value in [JSONValue.object(initial.mapValues(JSONValue.string)), .object(mixed.mapValues(JSONValue.string)), .object(initial.mapValues { _ in .string("1") }), .null, .object([:])] {
   var state = compatible; state["ipv6"] = value; try LaunchService.compatibility(state); check(true,"compatibility permits enabled/disabled/mixed/unknown/unreadable IPv6")
  }
  let transportSource = try String(contentsOfFile: "Core/SSHTransport.swift")
  check(transportSource.contains("ProxyCommand=false"), "lost master cannot fallback to new authentication")
  print("\(count) network checks PASS; isolated fixtures, no real Guest writes or game launch")
 }
}
