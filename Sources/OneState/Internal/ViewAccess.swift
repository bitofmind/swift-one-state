import Foundation

class ViewAccess: StoreAccess, ObservableObject {
    var contexts: [ContextBase] = []
    var observationTasks: [Task<(), Never>] = []
    var lock = Lock()
    var observedStates: [AnyKeyPath: (AnyStateChange) -> Bool] = [:]
    var wasStateOverriden = false
    var lastStateChange: AnyStateChange?

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    override func willAccess(path: AnyKeyPath, didUpdate: @escaping (AnyStateChange) -> Bool) {
        let wasAdded = lock {
            guard observedStates.index(forKey: path) == nil else { return false }

            observedStates[path] = { update in
                didUpdate(update)
            }

            return true
        }

        if wasAdded {
            Task { @MainActor in
                apply(callContexts: CallContext.currentContexts) {
                    objectWillChange.send()
                }
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
                objectWillChange.send()
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
                guard equal(update) else {
                    self.lastStateChange = update
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
