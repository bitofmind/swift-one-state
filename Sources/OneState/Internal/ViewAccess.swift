import Foundation

class ViewAccess: StoreAccess, ObservableObject {
    private var lock = Lock()
    private var observations: [ObjectIdentifier: Observation] = [:]
    private(set) var updateCount = 0
    private var modifyCount = 0

    override func willAccess<StoreModel: Model, Comparable: ComparableValue>(store: Store<StoreModel>, from context: ContextBase, path: KeyPath<StoreModel.State, Comparable.Value>, comparable: Comparable.Type) {
        let modifyCount = lock { self.modifyCount }
        let observedState: ObservedState? = lock {
            let id = ObjectIdentifier(context)

            let observation = observations[id] ?? {
                let observation = Observation(context: context) { [weak self] update in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.updateCount &+= 1
                        apply(callContexts: update.callContexts) {
                            self.objectWillChange.send()
                        }
                    }
                }

                observations[id] = observation
                return observation
            }()

            guard observation.observedStates.index(forKey: path) == nil else { return nil }

            let observedState = _ObservedState(store: store, path: path, comparable: comparable)
            observation.observedStates[path] = observedState

            return observedState
        }

        if let observedState {
            Task { @MainActor in
                // Handle race where an update might not be picked up due to observation not being fully active yet
                let wasModified = lock { self.modifyCount != modifyCount }
                let didUpdate = observedState.update()
                if wasModified || didUpdate {
                    apply(callContexts: CallContext.currentContexts) {
                        objectWillChange.send()
                    }
                }
            }
        }
    }

    override func didModify<S>(state: S) {
        lock { modifyCount &+= 1 }
    }

    override var allowAccessToBeOverridden: Bool { true }
}

private class ObservedState {
    func update() -> Bool { fatalError() }
    func onUpdate(_ update: StateUpdate, in context: ContextBase) -> Bool { fatalError() }
}

private final class _ObservedState<StoreModel: Model, Comparable: ComparableValue>: ObservedState {
    private var lock = Lock()
    weak var store: Store<StoreModel>?
    let path: KeyPath<StoreModel.State, Comparable.Value>
    var value: Comparable

    init(store: Store<StoreModel>, path: KeyPath<StoreModel.State, Comparable.Value>, comparable: Comparable.Type) {
        self.store = store
        self.path = path
        self.value = Comparable(value: store[overridePath: path] ?? store[path: path])
   }

    override func update() -> Bool {
        lock {
            guard let store else { return false }

            let newValue = Comparable(value: store[overridePath: path] ?? store[path: path])

            defer { value = newValue }
            return newValue != value
        }
    }

    override func onUpdate(_ update: StateUpdate, in context: ContextBase) -> Bool {
        let shouldUpdate = lock {
            guard !context.hasBeenRemoved else {
                return false
            }

            if Comparable.ignoreChildUpdates, update.fromContext.isDescendant(of: context) {
                return false
            }

            return true
        }

        return shouldUpdate && self.update()
    }
}

private final class Observation {
    var lock = Lock()
    var cancel: () -> Void = {}
    var observedStates: [AnyKeyPath: ObservedState] = [:]
    var wasStateOverriden = false

    init(context: ContextBase, onChange: @escaping (StateUpdate) -> Void) {
        cancel = Task { [weak self] in
            for await update in context.stateUpdates where !Task.isCancelled {
                guard let self, update.isStateOverridden == update.isOverrideUpdate else { continue }

                let wasUpdated = self.didUpdate(for: update, from: context)
                guard wasUpdated else { continue }

                onChange(update)
            }
        }.cancel
    }

    deinit {
        cancel()
    }

    func didUpdate(for update: StateUpdate, from context: ContextBase) -> Bool {
        if wasStateOverriden != update.isStateOverridden {
            wasStateOverriden = update.isStateOverridden
            return true
        }

        return observedStates.values.reduce(false) {
            $1.onUpdate(update, in: context) || $0
        }
    }
}
