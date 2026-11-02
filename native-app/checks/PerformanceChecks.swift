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
        print("\(passed) performance inference checks PASS")
    }
}
