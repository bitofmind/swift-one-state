import CustomDump
import Dependencies

final class ChildContext<StoreModel: Model, ContextModel: Model>: Context<ContextModel.State> {
    typealias StoreState = StoreModel.State
    typealias State = ContextModel.State

    @Dependency(\.uuid) private var _marker

    let store: Store<StoreModel>
    let path: WritableKeyPath<StoreState, State>
    private var _models: [ObjectIdentifier: ContextModel] = [:]
    private var modelLock = Lock()

    init(store: Store<StoreModel>, path: WritableKeyPath<StoreState, State>, parent: ContextBase?) {
        self.store = store
        self.path = path
        super.init(parent: parent)
    }

    var model: ContextModel {
        let access = StoreAccess.current?.value
        let key = access.map(ObjectIdentifier.init) ?? ObjectIdentifier(self)
        if let model = lock({ _models[key] }) { return model }

        return modelLock {
            let firstAccess = lock { _models.isEmpty }
            ThreadState.current.propertyIndex = 0
            ThreadState.current.dependencyIndex = 0
            let model = ContextBase.$current.withValue(self) {
                ContextModel()
            }

            guard !self.hasBeenRemoved else {
                return model
            }

            lock {
                _models[key] = model

                for (key, value) in _models {
                    if value.modelState?.storeAccess == nil && key != ObjectIdentifier(self) {
                        _models[key] = nil
                    }
                }
            }

            if firstAccess && !self.isOverrideContext {
                ContextBase.$current.withValue(nil) {
                    withCancellationContext(activateContextKey) {
                        model.onActivate()
                    }
                }
            }

            return model
        }
    }

    override func getModel<M: Model>() -> M {
        model as! M
    }

    override func onRemoval() {
        super.onRemoval()
        lock { _models.removeAll() }
    }

    override subscript<T> (path path: KeyPath<State, T>) -> T {
        _read {
            yield store[path: self.path.appending(path: path)]
        }
    }

    override subscript<T> (path path: WritableKeyPath<State, T>) -> T {
        _read {
            yield store[path: self.path.appending(path: path), fromContext: self]
        }
        _modify {
            yield &store[path: self.path.appending(path: path), fromContext: self]
        }
    }

    override subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read {
            yield store[overridePath: self.path.appending(path: path)]
        }
    }

    override func storePath<StoreState, T>(for path: WritableKeyPath<State, T>) -> WritableKeyPath<StoreState, T>? {
        self.path.appending(path: path) as? WritableKeyPath<StoreState, T>
    }

    override var isStateOverridden: Bool {
        store.stateOverride != nil
    }

    override func sendEvent(_ eventInfo: EventInfo, to receivers: EventReceivers) {
        if receivers.contains(.self) {
            events.yield(eventInfo)
        }

        if receivers.contains(.ancestors) {
            parent?.sendEvent(eventInfo, to: [.self, .ancestors])
        } else if receivers.contains(.parent) {
            parent?.sendEvent(eventInfo, to: .self)
        }

        if receivers.contains(.descendants) {
            for child in regularChildren.values {
                child.sendEvent(eventInfo, to: [.self, .descendants])
            }
        } else if receivers.contains(.children) {
            for child in regularChildren.values {
                child.sendEvent(eventInfo, to: .self)
            }
        }
    }

    override var storePath: AnyKeyPath { path }

    private func context<M: Model>(at path: WritableKeyPath<State, M.State>) -> ChildContext<StoreModel, M> {
        let isInViewModelContext = StoreAccess.isInViewModelContext
        let hasBeenRemoved = self.hasBeenRemoved

        lock.lock()
        defer { lock.unlock() }
        
        if isInViewModelContext, let context = _children[path] {
            return (context as! ChildContext<StoreModel, M>)
        } else if !isInViewModelContext, let context = _allChildren[path] {
            return (context as! ChildContext<StoreModel, M>)
        } else if parent == nil && !hasBeenRemoved && path == (\State.self as AnyKeyPath) {
            return (self as! ChildContext<StoreModel, M>)
        } else {
            let contextValue = self[path: \.self, access: nil]
            ThreadState.current.stateModelCount = 0
            _ = contextValue[keyPath: path]
            assert(ThreadState.current.stateModelCount <= 1, "Don't skip middle models when accessing sub model")

            let context = ChildContext<StoreModel, M>(store: store, path: self.path.appending(path: path), parent: self)

            if hasBeenRemoved {
                context.removeRecursively()
                return context
            }

            if isInViewModelContext || !isStateOverridden {
                _children[path] = context
            } else {
                context.isOverrideContext = true
                _overrideChildren[path] = context
            }
            
            lock.unlock()
            updateContainers()
            lock.lock()

            return context
        }
    }

    override func model<M: Model>(at path: WritableKeyPath<State, M.State>) -> M {
        context(at: path).model
    }

    override func didModify(for access: StoreAccess) {
        access.didModify(state: store.state)
    }

    override var cancellations: Cancellations {
        store.cancellations
    }

    override func value<Comparable: ComparableValue>(for path: KeyPath<State, Comparable.Value>, access: StoreAccess?, comparable: Comparable.Type) -> Comparable.Value {
        if !StoreAccess.isInViewModelContext, let access = access {
            let fullPath = self.path.appending(path: path)
            access.willAccess(store: store, from: self, path: fullPath, comparable: comparable)
        }

        return self[path: path, access: access]
    }

    override func withDependencies<Value>(_ operation: () -> Value) -> Value  {
        if let parent {
            return parent.withDependencies {
                withLocalDependencies(operation)
            }
        } else {
            return store.withLocalDependencies {
                withLocalDependencies(operation)
            }
        }
    }

    override var typeDescription: String {
        String(describing: ContextModel.self)
    }
}
