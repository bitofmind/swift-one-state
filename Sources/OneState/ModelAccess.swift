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
            guard observedStates.index(forKey: path) == nil else { return }

            observedStates[path] = { [weak context] update in
                guard let context = context else { return false }

                return isSame(
                    context[path: path, shared: update.current],
                    context[path: path, shared: update.previous]
                )
            }
        }
    }

    override var allowAccessToBeOverridden: Bool { true }
}

extension ModelAccess {
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

    var isObservering: Bool {
        observationTask != nil
    }
}

private extension ModelAccess {
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
                    print("previous", context[path: \.self, shared: update.previous])
                    print("current", context[path: \.self, shared: update.current])
#endif
                    return true
                }
            }

            return false
        }

        guard wasUpdated else { return }

        let callContext = update.callContext ?? .empty
        callContext(objectWillChange.send)
    }
}
