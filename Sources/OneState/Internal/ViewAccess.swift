import Foundation

class ViewAccess: StoreAccess, ObservableObject {
    var contexts: [ContextBase] = []
    var observationTasks: [Task<(), Never>] = []
    var lock = Lock()
    var observedStates: [AnyKeyPath: (AnyStateChange, ContextBase) -> Bool] = [:]
    var wasStateOverriden = false

    deinit {
        contexts.forEach { $0.activationRelease() }
        observationTasks.forEach { $0.cancel() }
    }

    override func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) {
        lock {
            guard observedStates.index(forKey: path) == nil else { return }

            observedStates[path] = { [weak context] update, fromContext in
                guard let context = context, context === fromContext else { return false }

                return isSame(
                    context[path: path, shared: update.current],
                    context[path: path, shared: update.previous]
                )
            }
        }
    }

    override var allowAccessToBeOverridden: Bool { true }
}

extension ViewAccess {
    func startObserving(from contexts: [ContextBase]) {
        stopObserving()
        self.contexts = contexts
        observationTasks = contexts.map { context in
            Task { @MainActor [weak self] in
                for await update in context.stateUpdates where !Task.isCancelled {
                    await self?.handle(update: update, for: context)
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

private extension ViewAccess {
    @MainActor func handle(update: AnyStateChange, for context: ContextBase) async {
        guard update.isStateOverridden == update.isOverrideUpdate else { return }

        let wasUpdated: Bool = lock {
            if wasStateOverriden != update.isStateOverridden {
                wasStateOverriden = update.isStateOverridden
                return true
            }

            for equal in observedStates.values {
                guard equal(update, context) else {
                    return true
                }
            }

            return false
        }

        guard wasUpdated else { return }

        apply(callContexts: update.callContexts) {
            objectWillChange.send()
        }
    }
}
