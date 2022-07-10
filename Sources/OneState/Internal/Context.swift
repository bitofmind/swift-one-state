class Context<State>: ContextBase {
    subscript<T> (path path: KeyPath<State, T>) -> T {
        _read { fatalError() }
    }

    subscript<T> (path path: WritableKeyPath<State, T>) -> T {
        _read { fatalError() }
        _modify { fatalError() }
    }

    subscript<T> (path path: KeyPath<State, T>, shared shared: AnyObject) -> T {
        _read { fatalError() }
    }

    subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read { fatalError() }
    }

    func context<T>(at path: WritableKeyPath<State, T>) -> Context<T> { fatalError() }

    var storePath: AnyKeyPath { fatalError() }

    func sendEvent(_ event: Any, context: ContextBase, callContext: CallContext?) {
        sendEvent(event, path: storePath, context: context, callContext: callContext)
    }
}

extension Context {
    subscript<T>(path path: WritableKeyPath<State, T>, access access: StoreAccess?) -> T {
        _read {
            if access?.allowAccessToBeOverridden == true, let override = self[overridePath: path] {
                yield override
            } else {
                yield self[path: path]
            }
        }
        _modify {
            yield &self[path: path]
        }
    }

    subscript<T>(path path: KeyPath<State, T>, access access: StoreAccess?) -> T {
        _read {
            if access?.allowAccessToBeOverridden == true, let override = self[overridePath: path] {
                yield override
            } else {
                yield self[path: path]
            }
        }
    }
}

extension Context {
    func value<T>(for path: KeyPath<State, T>, access: StoreAccess?, isSame: @escaping (T, T) -> Bool) -> T {
        if !StoreAccess.isInViewModelContext, let access = access {
            access.willAccess(path: path, context: self, isSame: isSame)
        }
        return self[path: path, access: access]
    }

    func value<T: Equatable>(for path: KeyPath<State, T>, access: StoreAccess?) -> T {
        value(for: path, access: access, isSame: ==)
    }
}

