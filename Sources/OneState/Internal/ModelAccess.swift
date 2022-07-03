import Foundation

class ModelAccess: StoreAccess, ObservableObject {
    var contexts: [ContextBase] = []
    var observationTasks: [Task<(), Never>] = []
    var lock = Lock()
    var observedStates: [AnyKeyPath: (AnyStateChange) -> Bool] = [:]
    var wasStateOverriden = false

    deinit {
        contexts.forEach { $0.releaseFromView() }
        observationTasks.forEach { $0.cancel() }
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
    func startObserving(from contexts: [ContextBase]) {
        stopObserving()
        self.contexts = contexts
        observationTasks = contexts.map { context in
            Task { @MainActor [weak self] in
                for await update in context.stateUpdates where !Task.isCancelled {
                    self?.handle(update: update)
                }
            }
        }
    }

    func stopObserving() {
        contexts.removeAll()
        observationTasks.forEach { $0.cancel() }
        observationTasks.removeAll()
        observedStates.removeAll()
        wasStateOverriden = false
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
