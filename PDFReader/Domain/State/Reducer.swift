protocol Reducer<State, Action, Environment> {
    associatedtype State
    associatedtype Action
    // WHY a default of Void: a reducer with no external dependency shouldn't have to spell out an empty
    // Environment type just to conform.
    associatedtype Environment = Void

    // WHY `into`: names the state as the thing being mutated in place, matching `inout`'s own contract —
    // a reducer answers "what happens to this action" and never returns a new State to assign over the old.
    // WHY `environment` as an explicit parameter rather than a stored property on the conforming type: see §1.
    func reduce(into state: inout State, action: Action, environment: Environment) -> Effect<Action>
}
