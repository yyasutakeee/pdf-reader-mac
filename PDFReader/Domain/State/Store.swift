import Combine

/// A generic single source of truth. Every application-specific input is supplied at construction.
/// Never subclass this type to add application behavior.
@dynamicMemberLookup
final class Store<State, Action, Environment>: ObservableObject {
    private(set) var state: State

    subscript<Value>(dynamicMember keyPath: KeyPath<State, Value>) -> Value {
        self.state[keyPath: keyPath]
    }

    /// Publishes the state AFTER every dispatch, carrying the new value as its element.
    let didChange: PassthroughSubject<State, Never> = PassthroughSubject<State, Never>()

    private let environment: Environment
    private let reduce: (inout State, Action, Environment) -> Effect<Action>
    private let logAction: (Action) -> Void
    private let runningEffectStore: RunningEffectStore = RunningEffectStore()

    init<R: Reducer>(
        initialState: State,
        reducer: R,
        environment: Environment,
        logAction: @escaping (Action) -> Void = { _ in }
    ) where R.State == State, R.Action == Action, R.Environment == Environment {
        self.state = initialState
        self.environment = environment
        self.reduce = reducer.reduce
        self.logAction = logAction
    }

    deinit {
        self.runningEffectStore.cancelAllEffectTasks()
    }

    @discardableResult
    func dispatch(_ action: Action) -> Effect<Action> {
        self.logAction(action)
        objectWillChange.send()
        let effect: Effect<Action> = self.reduce(&self.state, action, self.environment)
        didChange.send(self.state)
        self.runEffect(effect)
        return effect
    }

    private func runEffect(_ effect: Effect<Action>) {
        switch effect.operation {
        case .none:
            break
        case .send(let action):
            self.dispatch(action)
        case .merge(let effects):
            effects.forEach { self.runEffect($0) }
        case .cancel(let identifier):
            self.runningEffectStore.cancelEffectTask(identifier: identifier)
        case .run(let identifier, let work):
            self.startEffectWork(identifier: identifier, work: work)
        }
    }

    private func startEffectWork(
        identifier: AnyHashable?,
        work: @escaping (@escaping (Action) -> Void) async -> Void
    ) {
        self.runningEffectStore.startEffectTask(identifier: identifier) { [weak self] in
            await work { action in self?.dispatch(action) }
        }
    }
}
