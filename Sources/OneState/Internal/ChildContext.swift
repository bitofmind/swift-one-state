final class ChildContext<M: Model, State>: Context<State> {
    typealias Root = M.State

    let fallbackStore: Store<M>
    weak var weakStore: Store<M>?
    let path: WritableKeyPath<Root, State>

    init(store: Store<M>, path: WritableKeyPath<Root, State>, parent: ContextBase?) {
        weakStore = store
        fallbackStore = store.fallbackStore
        self.path = path
        super.init(parent: parent)
    }

    var store: Store<M> {
        assert(weakStore != nil, "Attempt to access a store that has been released")
        return weakStore ?? fallbackStore
    }

    override subscript<T> (path path: KeyPath<State, T>) -> T {
        _read {
            yield store[path: self.path.appending(path: path), fromContext: self]
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

    override subscript<T> (path path: KeyPath<State, T>, shared shared: AnyObject) -> T {
        _read {
            yield store[path: self.path.appending(path: path), shared: shared]
        }
    }

    override subscript<T> (path path: WritableKeyPath<State, T>, shared shared: AnyObject) -> T {
        _read {
            yield store[path: self.path.appending(path: path), shared: shared]
        }
        _modify {
            yield &store[path: self.path.appending(path: path), shared: shared]
        }
    }

    override subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read {
            yield store[overridePath: self.path.appending(path: path)]
        }
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

    override func context<T>(at path: WritableKeyPath<State, T>) -> Context<T> {
        lock {
            let isInViewModelContext = StoreAccess.isInViewModelContext

            if isInViewModelContext, let context = _children[path] {
                return context as! Context<T>
            } else if !isInViewModelContext, let context = _allChildren[path] {
                return context as! Context<T>
            } else if parent == nil && path == (\State.self as AnyKeyPath) {
                let context = self as! Context<T>
                return context
            } else {
                let contextValue = self[path: \.self, access: nil]
                ThreadState.current.stateModelCount = 0
                _ = contextValue[keyPath: path]
                assert(ThreadState.current.stateModelCount <= 1, "Don't skip middle models when accessing sub model")

                let context = ChildContext<M, T>(store: store, path: self.path.appending(path: path), parent: self)

                if isInViewModelContext || !isStateOverridden {
                    _children[path] = context
                } else {
                    _overrideChildren[path] = context
                }

                return context
            }
        }
    }

    override func pushTask(_ info: TaskInfo) {
        weakStore?.pushTask(info)
    }

    override func popTask(_ info: TaskInfo) {
        weakStore?.popTask(info)
    }

    override func didModify(for access: StoreAccess) {
        access.didModify(state: store.sharedState)
    }
}
