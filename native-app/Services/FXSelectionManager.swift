import Foundation

/// One persisted choice; discovery and launch capability remain separate evidence.
struct FXSelectionManager {
    private let defaults: UserDefaults?
    private(set) var selectedPath: String?
    private(set) var automatic: Bool
    private(set) var candidates: [[String: JSONValue]] = []
    private(set) var scanned = false
    var selected: [String: JSONValue]? { candidates.first { $0["path"]?.text == selectedPath } }
    var scanPaths: [JSONValue] { selectedPath.map { [.string($0)] } ?? [] }
    func launchParameters(runtimeRoot: String) -> [String: JSONValue] {
        ["runtime_root": .string(runtimeRoot), "fx_path": .string(selectedPath ?? "")]
    }

    init(defaults: UserDefaults? = .standard) {
        self.defaults = defaults
        selectedPath = defaults?.string(forKey: "NativeDefaultFXPath")
        automatic = defaults?.bool(forKey: "NativeDefaultFXAutomatic") ?? false
    }
    mutating func reconcile(_ rows: [[String: JSONValue]], incomplete: Bool) {
        candidates = rows.filter { $0["identity_valid"]?.boolean == true && $0["structure"]?.text == "metadata_valid" }
        scanned = true
        if selected != nil { return }
        // An incomplete scan is not evidence that a remembered installation vanished.
        // Keep the path, but selected stays nil until fresh identity evidence is available.
        if incomplete && selectedPath != nil { return }
        // Scan scope warnings remain visible; selection never claims launch readiness.
        if candidates.count == 1 {
            select(candidates[0]["path"]?.text, automatic: true)
        } else {
            select(nil, automatic: false)
        }
    }
    mutating func select(_ path: String?, automatic: Bool = false) {
        guard path == nil || candidates.contains(where: { $0["path"]?.text == path }) else { return }
        selectedPath = path; self.automatic = automatic
        if let path { defaults?.set(path, forKey: "NativeDefaultFXPath") }
        else { defaults?.removeObject(forKey: "NativeDefaultFXPath") }
        defaults?.set(automatic, forKey: "NativeDefaultFXAutomatic")
    }
}
