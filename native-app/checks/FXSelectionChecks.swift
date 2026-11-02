import Foundation

@main struct FXSelectionChecks {
    static func main() throws {
        var checks = 0
        func check(_ ok: Bool, _ name: String) throws {
            guard ok else { throw NSError(domain: name, code: 1) }
            checks += 1
        }
        func row(_ path: String, _ version: String = "1.9.8") -> [String: JSONValue] {
            ["path": .string(path), "version": .string(version), "identity_valid": .bool(true), "structure": .string("metadata_valid"), "launch": .string("unverified")]
        }
        let suite = "hd2-fx-selection-fixture-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var manager = FXSelectionManager(defaults: defaults)
        manager.reconcile([], incomplete: false)
        try check(manager.selected == nil, "zero candidates")
        manager.reconcile([row("/fixture/A.app")], incomplete: false)
        try check(manager.selectedPath == "/fixture/A.app" && manager.automatic, "single candidate automatically selected")
        try check(manager.selected?["launch"]?.text == "unverified", "structure never proves launch")
        manager = FXSelectionManager(defaults: defaults)
        manager.reconcile([row("/fixture/A.app")], incomplete: false)
        try check(manager.selectedPath == "/fixture/A.app" && manager.automatic, "restored across app restart")
        manager.reconcile([row("/fixture/A.app"), row("/fixture/B.app", "99.0")], incomplete: false)
        try check(manager.selectedPath == "/fixture/A.app", "multiple preserves existing default regardless of version")
        manager.select("/fixture/B.app")
        manager.reconcile([row("/fixture/A.app", "999.0"), row("/fixture/B.app")], incomplete: false)
        try check(manager.selectedPath == "/fixture/B.app" && !manager.automatic, "manual choice is never overwritten")
        manager.reconcile([row("/fixture/B.app", "2.0")], incomplete: false)
        try check(manager.selected?["version"]?.text == "2.0" && !manager.automatic, "version update refreshes evidence while retaining manual default")
        manager.reconcile([row("/fixture/A.app")], incomplete: false)
        try check(manager.selectedPath == "/fixture/A.app" && manager.automatic, "deleted default replaced by sole valid candidate")
        manager.reconcile([row("/moved/A.app")], incomplete: false)
        try check(manager.selectedPath == "/moved/A.app", "moved default replaced and saved")
        manager.reconcile([row("/fixture/C.app"), row("/fixture/D.app")], incomplete: false)
        try check(manager.selectedPath == nil, "missing default and two candidates requires choice")
        manager.reconcile([row("/fixture/C.app"), row("/fixture/D.app")], incomplete: false)
        try check(manager.selected == nil, "two candidates never auto-sort by version")
        manager.reconcile([["path": .string("/fake.app"), "structure": .string("metadata_valid")]], incomplete: false)
        try check(manager.selected == nil, "unverified identity rejected")
        manager.reconcile([row("/fixture/A.app")], incomplete: true)
        try check(manager.selectedPath == "/fixture/A.app", "sole verified result selected while scan scope warning remains separate")
        manager.reconcile([row("/fixture/A.app")], incomplete: false)
        manager.reconcile([], incomplete: false)
        try check(FXSelectionManager(defaults: defaults).selectedPath == nil, "invalid default cleared persistently")
        print("PASS: \(checks) FX selection checks; no processes or game started")
    }
}
