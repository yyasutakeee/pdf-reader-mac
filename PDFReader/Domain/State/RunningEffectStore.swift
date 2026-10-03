final class RunningEffectStore {
    private var runningTasks: [AnyHashable: Task<Void, Never>] = [:]

    // WHY: an unidentified effect is fire-and-forget and never needs remembering; an identified one replaces
    // its own predecessor, which is what makes re-running the same effect idempotent instead of doubling it.
    // Pinned to the main actor for the task's whole lifetime so effect actions return to Store in order.
    func startEffectTask(identifier: AnyHashable?, work: @escaping () async -> Void) {
        guard let identifier else {
            Task { @MainActor in await work() }
            return
        }
        self.cancelEffectTask(identifier: identifier)
        self.runningTasks[identifier] = Task { @MainActor in await work() }
    }

    func cancelEffectTask(identifier: AnyHashable) {
        self.runningTasks[identifier]?.cancel()
        self.runningTasks[identifier] = nil
    }

    func cancelAllEffectTasks() {
        self.runningTasks.values.forEach { $0.cancel() }
        self.runningTasks.removeAll()
    }
}
