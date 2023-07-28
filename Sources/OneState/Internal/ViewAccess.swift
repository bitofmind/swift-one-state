import Foundation

class ViewAccess: StoreAccess, ObservableObject {
    private var lock = Lock()
    private var observations: [ObjectIdentifier: Observation] = [:]
    private(set) var updateCount = 0

    override func willAccess<StoreModel: ModelContainer, Comparable: ComparableValue>(store: InternalStore<StoreModel>, from context: ContextBase, path: KeyPath<StoreModel.Container, Comparable.Value>, comparable: Comparable.Type) {
        lock {
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

            observation.lock {
                guard observation.observedStates.index(forKey: path) == nil else { return }
                
                observation.observedStates[path] = _ObservedState(store: store, path: path, comparable: comparable)
            }
        }
    }

    override var allowAccessToBeOverridden: Bool { true }

    func reset() {
        lock {
            observations.removeAll(keepingCapacity: true)
        }
    }
}

private class ObservedState {
    func onUpdate(_ update: StateUpdate, in context: ContextBase) -> Bool { fatalError() }
}

private final class _ObservedState<StoreModel: ModelContainer, Comparable: ComparableValue>: ObservedState {
    weak var store: InternalStore<StoreModel>?
    let path: KeyPath<StoreModel.Container, Comparable.Value>
    var value: Comparable

    init(store: InternalStore<StoreModel>, path: KeyPath<StoreModel.Container, Comparable.Value>, comparable: Comparable.Type) {
        self.store = store
        self.path = path
        self.value = Comparable(value: store[overridePath: path] ?? store[path: path])
    }

    override func onUpdate(_ update: StateUpdate, in context: ContextBase) -> Bool {
        guard let store, !context.hasBeenRemoved else {
            return false
        }

        if Comparable.ignoreChildUpdates, update.fromContext.isDescendant(of: context) {
            return false
        }

        let newValue = Comparable(value: store[overridePath: path] ?? store[path: path])

        defer { value = newValue }
        return newValue != value
    }
}

private final class Observation {
    var lock = Lock()
    var cancel: () -> Void = {}
    var observedStates: [AnyKeyPath: ObservedState] = [:]
    var wasStateOverridden = false

    init(context: ContextBase, onChange: @escaping (StateUpdate) -> Void) {
        let stateUpdates = context.stateUpdates
        cancel = Task { [weak self, weak context] in
            for await update in stateUpdates where !Task.isCancelled {
                guard let self, let context, update.isStateOverridden == update.isOverrideUpdate else { continue }

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
        lock {
            if wasStateOverridden != update.isStateOverridden {
                wasStateOverridden = update.isStateOverridden
                return true
            }

            return observedStates.values.reduce(false) {
                $1.onUpdate(update, in: context) || $0
            }
        }
    }
}
