struct Effect<Action> {
    indirect enum Operation {
        case none
        case send(Action)                 // re-dispatch another action, synchronously
        case merge([Effect<Action>])      // several effects from one dispatch
        case run(identifier: AnyHashable?, work: (@escaping (Action) -> Void) async -> Void)
        case cancel(identifier: AnyHashable)
    }
    let operation: Operation

    static var none: Effect<Action> { Effect(operation: .none) }
    static func send(_ action: Action) -> Effect<Action> { Effect(operation: .send(action)) }
    static func run(identifier: AnyHashable? = nil,
                    _ work: @escaping (@escaping (Action) -> Void) async -> Void) -> Effect<Action> {
        Effect(operation: .run(identifier: identifier, work: work))
    }
    static func cancel(identifier: AnyHashable) -> Effect<Action> { Effect(operation: .cancel(identifier: identifier)) }

    static func merge(_ effects: [Effect<Action>]) -> Effect<Action> {
        let runnable = effects.filter { if case .none = $0.operation { return false } else { return true } }
        guard !runnable.isEmpty else { return .none }
        guard runnable.count > 1 else { return runnable[0] }
        return Effect(operation: .merge(runnable))
    }

    // WHY: lifts an effect describing one domain's own action type into a parent's action type, so a
    // sub-reducer never needs to know the parent action exists — the parent reducer does the lifting at
    // its one call site instead of every child reducer wrapping its own effects.
    func map<NewAction>(_ transform: @escaping (Action) -> NewAction) -> Effect<NewAction> {
        switch operation {
        case .none:
            return .none
        case .send(let action):
            return .send(transform(action))
        case .merge(let effects):
            return Effect<NewAction>.merge(effects.map { $0.map(transform) })
        case .cancel(let identifier):
            return .cancel(identifier: identifier)
        case .run(let identifier, let work):
            return .run(identifier: identifier) { dispatch in
                await work { action in dispatch(transform(action)) }
            }
        }
    }
}
