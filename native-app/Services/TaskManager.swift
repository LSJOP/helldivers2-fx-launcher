import Foundation

@MainActor
final class TaskManager: ObservableObject {
    @Published private(set) var busy = false
    private var task: Task<Void, Never>?
    private var completion: (() -> Void)?
    @discardableResult
    func start(_ operation: @escaping @MainActor () async -> Void) -> Bool {
        guard !busy else { return false }
        busy = true
        task = Task {
            await operation()
            let next = Task.isCancelled ? nil : completion
            completion = nil; busy = false; task = nil
            next?()
        }
        return true
    }
    func afterCurrent(_ operation: @escaping () -> Void) {
        guard busy else { return }
        completion = operation
    }
    func cancel() { completion = nil; task?.cancel() }
}
