import Foundation
@main struct TaskManagerChecks {
    @MainActor static func main() async throws {
        let manager = TaskManager()
        var order = [String]()
        func wait() async throws { while manager.busy { try await Task.sleep(nanoseconds: 1_000_000) } }
        func check(_ condition: Bool, _ label: String) {
            guard condition else { fatalError(label) }; print("PASS " + label)
        }
        check(manager.start { order.append("first"); manager.afterCurrent {
            check(!manager.busy, "continuation starts after busy is released")
            manager.start { order.append("second") }
        } }, "initial task accepted")
        check(!manager.start { order.append("duplicate") }, "duplicate task rejected")
        try await wait()
        check(order == ["first", "second"], "one ordered continuation executes")
        manager.start {
            manager.afterCurrent { order.append("cancelled continuation") }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        await Task.yield()
        manager.cancel()
        try await wait()
        check(order == ["first", "second"], "cancel prevents queued continuation")
        print("5 task queue checks PASS; no runtime actions")
    }
}
