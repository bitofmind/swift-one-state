import Foundation

class ModelAccess<State>: StoreAccess, ObservableObject {
    var context: Context<State>!
    var observationTask: Task<(), Never>?
    var lock = Lock()
    var observedStates: [AnyKeyPath: (AnyStateChange) -> Bool] = [:]
    var wasStateOverriden = false

    deinit {
        context?.releaseFromView()
        observationTask?.cancel()
    }

    override func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) {
        lock {
            if observedStates.index(forKey: path) == nil {
                //print("will start observing:", path, type(of: self))

                observedStates[path] = { [weak context] update in
                    guard let context = context else { return false }

                    return isSame(
                        context.getShared(shared: update.current, path: path),
                        context.getShared(shared: update.previous, path: path)
                    )
                }
            }
        }
    }

    override var allowAccessToBeOverridden: Bool { true }

    var isObservering: Bool {
        observationTask != nil
    }

    func handle(update: AnyStateChange) {
        guard update.isStateOverridden == update.isOverrideUpdate else { return }

        let wasUpdated: Bool = lock {
            if wasStateOverriden != update.isStateOverridden {
                wasStateOverriden = update.isStateOverridden
                return true
            }

            for equal in observedStates.values {
                guard equal(update) else {
#if false
                    let previous = context.getShared(shared: update.previous, path: \State.self)
                    let current = context.getShared(shared: update.current, path: \State.self)
                    print("previous", previous)
                    print("current", current)
#endif
                    return true
                }
            }
            return false
        }

        if wasUpdated {
            (update.callContext ?? .empty) {
                objectWillChange.send()
            }
        }
    }

    func startObserve() {
        observationTask?.cancel()
        wasStateOverriden = context.isStateOverridden
        observationTask = Task { @MainActor [weak self] in
            guard let updates = self?.context.stateUpdates else { return }
            for await update in updates {
                self?.handle(update: update)
            }
        }
    }
}
