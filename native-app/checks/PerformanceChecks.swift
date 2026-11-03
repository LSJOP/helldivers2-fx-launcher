import Foundation

@main struct PerformanceChecks {
    static func main() throws {
        var passed=0
        func check(_ value: Bool, _ name: String) throws {
            guard value else { throw ErrorState("ASSERTION_FAILED", method:name) }
            passed += 1; print("PASS " + name)
        }
        let service=GamePerformanceInferenceService()
        let reference=JSONValue.object(GamePerformanceInferenceService.reference)
        func snapshot(_ chip: String, _ memory: Int) -> [String:JSONValue] {
            ["hardware":.object(["chip":.string(chip),"memory_bytes":.number(Double(memory))]),"reference":reference]
        }
        let matched=service.infer(snapshot("Apple M4 Pro",24*1024*1024*1024))
        try check(matched.kind == .localBaseline && !matched.writable,"exact historical device is a non-writable candidate, never verified performance")
        for chip in ["Apple M4 Max","Apple M3","Apple M5 Pro"] {
            let other=service.infer(snapshot(chip,24*1024*1024*1024))
            try check(other.kind == .unsupported && !other.writable,"no GPU-ratio interpolation: " + chip)
        }
        try check(service.infer(snapshot("Apple M4 Pro",48*1024*1024*1024)).kind == .unsupported,"different memory tier has no inferred writable profile")
        try check(service.infer([:]).reference.isEmpty,"missing hardware/source is not a fabricated default")
        var changed=snapshot("Apple M4 Pro",24*1024*1024*1024)
        changed["reference"] = .object(["cpus":.string("8")])
        try check(service.infer(changed).kind == .unsupported,"source mismatch and wrong types fail closed")
        try check(GamePerformanceInferenceService.differs(.null,.number(8)) == nil,"unknown current value is not treated as a difference or default")
        try check(GamePerformanceInferenceService.differs(.bool(false),.bool(false)) == false && GamePerformanceInferenceService.differs(.number(4),.number(8)) == true,"real current/baseline differences stay distinct")
        var editor = PerformanceConfigurationState()
        let original: [String: JSONValue] = ["current":.object(["cpus":.number(8)]), "revision":.string("a"), "effective":.string("unverified")]
        editor.acceptSnapshot(original)
        editor.edited["cpus"] = .number(6)
        try check(editor.current["cpus"]?.integer == 8 && editor.edited["cpus"]?.integer == 6, "unsaved edits cannot mutate current configuration")
        editor.acceptPreview(["plan":.object(["revision":.string("old")]), "token":.string("token")])
        try check(editor.preview.isEmpty, "stale preview cannot enter confirmation state")
        editor.acceptPreview(["plan":.object(["revision":.string("a")]), "token":.string("token")])
        try check(!editor.preview.isEmpty, "matching preview enters confirmation state")
        editor.preview = [:]
        try check(editor.current["cpus"]?.integer == 8, "cancel confirmation leaves saved state intact")
        editor.acceptSnapshot(["current":.object(["cpus":.number(6)]), "last_applied":.object(["cpus":.number(6)]), "backup":.object(["cpus":.number(8)]), "revision":.string("b")])
        try check(editor.current["cpus"]?.integer == 6 && editor.lastApplied["cpus"]?.integer == 6 && editor.backup["cpus"]?.integer == 8 && editor.preview.isEmpty, "successful read-back updates current, last-applied, backup and clears preview")
        try check(!editor.effectiveVerified, "successful save never establishes effective Guest configuration")
        print("\(passed) performance inference and editor state checks PASS")
    }
}
