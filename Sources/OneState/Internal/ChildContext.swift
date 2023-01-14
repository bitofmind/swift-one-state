import CustomDump

final class ChildContext<StoreModel: Model, ContextModel: Model>: Context<ContextModel.State> {
    typealias StoreState = StoreModel.State
    typealias State = ContextModel.State

    let store: Store<StoreModel>
    let path: WritableKeyPath<StoreState, State>
    private var _models: [ObjectIdentifier: ContextModel] = [:]
    private var modelLock = Lock()

    var model: ContextModel {
        let access = StoreAccess.current?.value
        let key = access.map(ObjectIdentifier.init) ?? ObjectIdentifier(self)
        if let model = lock({ _models[key] }) { return model }

        modelLock {
            let firstAccess = lock { _models.isEmpty }
            ThreadState.current.propertyIndex = 0
            let model = ContextBase.$current.withValue(self) {
                ContextModel()
            }
            lock { _models[key] = model }

            guard firstAccess, parent != nil, !self.isOverrideContext else { return }

            ContextBase.$current.withValue(nil) {
                model.onActivate()
            }
        }

        return self.model
    }

    override func getModel<M: Model>() -> M {
        model as! M
    }

    init(store: Store<StoreModel>, path: WritableKeyPath<StoreState, State>, parent: ContextBase?) {
        self.store = store
        self.path = path
        super.init(parent: parent)
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

    override func sendEvent(_ eventInfo: EventInfo) {
        Task {
            events.yield(eventInfo)
        }

        parent?.sendEvent(eventInfo)
    }

    override var storePath: AnyKeyPath { path }

    private func context<M: Model>(at path: WritableKeyPath<State, M.State>) -> ChildContext<StoreModel, M> {
        let isInViewModelContext = StoreAccess.isInViewModelContext

        if isInViewModelContext, let context = _children[path] {
            return (context as! ChildContext<StoreModel, M>)
        } else if !isInViewModelContext, let context = _allChildren[path] {
            return (context as! ChildContext<StoreModel, M>)
        } else if parent == nil && path == (\State.self as AnyKeyPath) {
            return (self as! ChildContext<StoreModel, M>)
        } else {
            let contextValue = self[path: \.self, access: nil]
            ThreadState.current.stateModelCount = 0
            _ = contextValue[keyPath: path]
            assert(ThreadState.current.stateModelCount <= 1, "Don't skip middle models when accessing sub model")

            let context = ChildContext<StoreModel, M>(store: store, path: self.path.appending(path: path), parent: self)

            if isInViewModelContext || !isStateOverridden {
                _children[path] = context
            } else {
                context.isOverrideContext = true
                _overrideChildren[path] = context
            }

            return context
        }
    }

    override func model<M: Model>(at path: WritableKeyPath<State, M.State>) -> M {
        let context: ChildContext<StoreModel, M> = lock { self.context(at: path) }
        return context.model
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
            access.willAccess(store: store, path: fullPath, comparable: comparable)
        }

        return self[path: path, access: access]
    }
}
