import Foundation

// FX instance identity regression checks. Pure fixtures only; no FX/ps/network is touched.
var passed = 0
var failed = 0
func ok(_ c: Bool, _ name: String) { if c { passed += 1; print("PASS \(name)") } else { failed += 1; print("FAIL \(name)") } }

func row(_ pid: Int, _ ppid: Int, _ command: String) -> LaunchService.ProcessRow {
    LaunchService.ProcessRow(pid: pid, ppid: ppid, start: "Tue Nov  3 22:27:41 2026", command: command)
}
let fxExe = "/Applications/FX Steam Launcher.app/Contents/MacOS/steamac-vm"
let otherExe = "/Applications/FX 绝地潜兵2（脚本专用）.app/Contents/MacOS/steamac-vm"

@main
struct FXIdentityChecks {
    static func main() {
        // 1. processTable parser: real ps format, multi-space columns, path with spaces.
        let sample = """
        55802     1 Tue Nov  3 22:27:41 2026     /Applications/FX Steam Launcher.app/Contents/MacOS/steamac-vm
        55809 55802 Tue Nov  3 22:27:41 2026     /Applications/FX Steam Launcher.app/Contents/MacOS/steamac-vm
        55804 55803 Tue Nov  3 22:27:41 2026     /Volumes/Thunderbolt2TB/HD2-App-Builds/Latest/HD2FXNative.app/Contents/Resources/launch/gvproxy-eim
        """
        let parsed = LaunchService.parseProcessTable(sample)
        ok(parsed[55802]?.ppid == 1, "parser ppid")
        ok(parsed[55809]?.ppid == 55802, "parser child ppid")
        ok(parsed[55802]?.command == fxExe, "parser full path with spaces")
        ok(parsed[55804]?.command.hasSuffix("gvproxy-eim") == true, "parser gvproxy path")

        // 2. fxSupervisorPID: single process.
        let single = [1: row(1, 99, fxExe)]
        ok((try? LaunchService.fxSupervisorPID(rows: single, executable: fxExe)) == 1, "supervisor: single process")

        // 3. fxSupervisorPID: supervisor + VM child (parent of child is the other process).
        let pair = [10: row(10, 1, fxExe), 11: row(11, 10, fxExe)]
        ok((try? LaunchService.fxSupervisorPID(rows: pair, executable: fxExe)) == 10, "supervisor: 2-process topology")

        // 4. fxSupervisorPID: zero processes.
        do { _ = try LaunchService.fxSupervisorPID(rows: [:], executable: fxExe); ok(false, "supervisor: none fails") }
        catch let e as CoreError { ok(e.code == "FX_IDENTITY_UNVERIFIED", "supervisor: none fails closed") }
        catch { ok(false, "supervisor: none unexpected") }

        // 5. fxSupervisorPID: more than two (unverified).
        let triple = [20: row(20, 1, fxExe), 21: row(21, 20, fxExe), 22: row(22, 20, fxExe)]
        do { _ = try LaunchService.fxSupervisorPID(rows: triple, executable: fxExe); ok(false, "supervisor: >2 fails") }
        catch let e as CoreError { ok(e.code == "FX_IDENTITY_UNVERIFIED", "supervisor: >2 fails closed") }
        catch { ok(false, "supervisor: >2 unexpected") }

        // 6. fxSupervisorPID: cycle (parent's parent == child) is rejected.
        let cycle = [30: row(30, 31, fxExe), 31: row(31, 30, fxExe)]
        do { _ = try LaunchService.fxSupervisorPID(rows: cycle, executable: fxExe); ok(false, "supervisor: cycle rejected") }
        catch let e as CoreError { ok(e.code == "FX_IDENTITY_UNVERIFIED", "supervisor: cycle rejected") }
        catch { ok(false, "supervisor: cycle unexpected") }

        // 7. foreignProcesses: same FX (both processes) is not foreign.
        ok(LaunchService.foreignProcesses(rows: pair, executable: fxExe).isEmpty, "foreign: same FX not foreign")

        // 8. foreignProcesses: a different copy is detected as foreign.
        let mixed = [40: row(40, 1, fxExe), 41: row(41, 40, otherExe)]
        let foreign = LaunchService.foreignProcesses(rows: mixed, executable: fxExe)
        ok(foreign.count == 1 && foreign.first?.command == otherExe, "foreign: different copy detected")

        // 9. normalizedCommand resolves a symlinked app path to the real path.
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("fx-identity-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: tmp.appendingPathComponent("real/Contents/MacOS", isDirectory: true), withIntermediateDirectories: true)
        try! Data("#!/bin/sh\nexit 0\n".utf8).write(to: tmp.appendingPathComponent("real/Contents/MacOS/steamac-vm"))
        let link = tmp.appendingPathComponent("Linked.app")
        try! FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: tmp.appendingPathComponent("real").path)
        let normalized = LaunchService.normalizedExecutable(link)
        ok(normalized == tmp.appendingPathComponent("real/Contents/MacOS/steamac-vm").resolvingSymlinksInPath().standardizedFileURL.path,
           "normalizedCommand resolves symlink")
        try? FileManager.default.removeItem(at: tmp)

        print("TOTAL \(passed) passed, \(failed) failed")
        exit(failed == 0 ? 0 : 1)
    }
}
