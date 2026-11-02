import Foundation

@MainActor
final class TaskManager: ObservableObject {
    @Published private(set) var busy = false
    private var task: Task<Void, Never>?
    @discardableResult
    func start(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard !busy else { return false }
        busy = true
        task = Task { await operation(); busy = false; task = nil }
        return true
    }
    func cancel() { task?.cancel() }
}
