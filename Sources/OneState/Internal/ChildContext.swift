import CustomDump

final class ChildContext<M: Model, State>: Context<State> {
    let store: Store<M>
    let path: WritableKeyPath<M.State, State>

    init(store: Store<M>, path: WritableKeyPath<M.State, State>, parent: ContextBase?) {
        self.store = store
        self.path = path
        super.init(parent: parent)
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

    override func didModify(for access: StoreAccess) {
        access.didModify(state: store.sharedState)
    }

    override func notify(_ update: AnyStateChange) {
        super.notify(update)

        let contextValue = self[path: \.self, access: nil]

        for (path, context) in allChildren {
            ThreadState.current.pathFallbackCount = 0
            _ = contextValue[keyPath: path]
            if ThreadState.current.pathFallbackCount > 0 {
                context.removeRecusively()
            }
        }
    }

    override var cancellations: Cancellations {
        store.cancellations
    }

    override func value<T>(for path: KeyPath<State, T>, access: StoreAccess?, isSame: @escaping (T, T) -> Bool) -> T {
        if !StoreAccess.isInViewModelContext, let access = access {
            let fullPath = self.path.appending(path: path)
            access.willAccess(path: fullPath) { [weak store] update in
                guard let store = store, update.current is Shared<M.State> else { return true }
                
                return isSame(
                    store[path: fullPath, shared: update.current],
                    store[path: fullPath, shared: update.previous]
                )
            }
        }

        return self[path: path, access: access]
    }

    override func diff(for change: AnyStateChange, at path: AnyKeyPath) -> String? {
        guard let current = change.current as? Shared<M.State>,
              let previous = change.previous as? Shared<M.State> else {
            return nil
        }

        guard let c = current.value[keyPath: path], let p = previous.value[keyPath: path] else {
            return nil
        }

        return CustomDump.diff(p, c)
    }
}
