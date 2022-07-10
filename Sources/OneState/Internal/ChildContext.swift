final class ChildContext<M: Model, State>: Context<State> {
    typealias Root = M.State

    let store: Store<M>
    let path: WritableKeyPath<Root, State>

    init(store: Store<M>, path: WritableKeyPath<Root, State>, parent: ContextBase?) {
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

    override subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read {
            yield store[overridePath: self.path.appending(path: path)]
        }
    }

    override var isStateOverridden: Bool {
        store.stateOverride != nil
    }

    override func sendEvent(_ event: Any, path: AnyKeyPath, context: ContextBase, callContext: CallContext?) {
        events.yield((event: event, path: path, context: context, callContext: callContext))
        parent?.sendEvent(event, path: path, context: context, callContext: callContext)
    }

    override var storePath: AnyKeyPath { path }

    override func context<T>(at path: WritableKeyPath<State, T>) -> Context<T> {
        let isInViewModelContext = StoreAccess.isInViewModelContext

        if isInViewModelContext, let context = regularChildren[path] {
            return context as! Context<T>
        } else if !isInViewModelContext, let context = allChildren[path] {
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

            if isInViewModelContext {
                regularChildren[path] = context
            } else {
                allChildren[path] = context
            }

            return context
        }
    }
}
