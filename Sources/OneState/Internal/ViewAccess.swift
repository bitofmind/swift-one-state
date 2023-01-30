import Foundation

class ViewAccess: StoreAccess, ObservableObject {
    private(set) var contexts: [ContextBase] = []
    private var observationTasks: [Task<(), Never>] = []
    var lock = Lock()
    private var observedStates: [AnyKeyPath: ObservedState] = [:]
    private var wasStateOverriden = false
    var updateCount = 0

    deinit {
        observationTasks.forEach { $0.cancel() }
    }

    override func willAccess<StoreModel: Model, Comparable: ComparableValue>(store: Store<StoreModel>, path: KeyPath<StoreModel.State, Comparable.Value>, comparable: Comparable.Type) {
        let wasAdded = lock {
            guard observedStates.index(forKey: path) == nil else { return false }

            observedStates[path] = _ObservedState(store: store, path: path, comparable: comparable)
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

private class ObservedState {
    func onUpdate(isFromChild: Bool) -> Bool { fatalError() }
}

private final class _ObservedState<StoreModel: Model, Comparable: ComparableValue>: ObservedState {
    weak var store: Store<StoreModel>?
    let path: KeyPath<StoreModel.State, Comparable.Value>
    var value: Comparable

    init(store: Store<StoreModel>, path: KeyPath<StoreModel.State, Comparable.Value>, comparable: Comparable.Type) {
        self.store = store
        self.path = path
        self.value = Comparable(value: store[overridePath: path] ?? store[path: path])
    }

    override func onUpdate(isFromChild: Bool) -> Bool {
        guard let store, !Comparable.ignoreChildUpdates || !isFromChild else {
            return false
        }

        let newValue = Comparable(value: store[overridePath: path] ?? store[path: path])

        defer { value = newValue }
        return newValue != value
    }
}

extension ViewAccess {
    func startObserving(from contexts: [ContextBase]) {
        stopObserving()
        self.contexts = contexts
        observationTasks = contexts.map {  [weak self] context in
            Task { @MainActor [weak self] in
                self?.objectWillChange.send()
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
    @MainActor func handle(update: StateChange, for context: ContextBase) async {
        guard update.isStateOverridden == update.isOverrideUpdate else { return }

        let wasUpdated: Bool = lock {
            if wasStateOverriden != update.isStateOverridden {
                wasStateOverriden = update.isStateOverridden
                return true
            }

            for observedState in observedStates.values {
                guard !observedState.onUpdate(isFromChild: update.isFromChild) else {
                    return true
                }
            }

            return false
        }

        guard wasUpdated else { return }

        updateCount += 1
        apply(callContexts: update.callContexts) {
            objectWillChange.send()
        }
    }
}
