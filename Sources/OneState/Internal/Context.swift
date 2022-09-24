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

    subscript<T> (path path: WritableKeyPath<State, T>, shared shared: AnyObject) -> T {
        _read { fatalError() }
        _modify { fatalError() }
    }

    subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read { fatalError() }
    }

    func value<T>(for path: KeyPath<State, T>, access: StoreAccess?, isSame: @escaping (T, T) -> Bool) -> T {
        fatalError()
    }

    func context<T>(at path: WritableKeyPath<State, T>) -> Context<T> { fatalError() }

    var storePath: AnyKeyPath { fatalError() }

    func sendEvent(_ event: Any, context: ContextBase, callContexts: [CallContext], storeAccess: StoreAccess?) {
        let eventInfo = EventInfo(event: event, path: storePath, context: context, callContexts: callContexts)
        sendEvent(eventInfo)
        storeAccess?.didSend(event: eventInfo)
    }

    func didModify(for access: StoreAccess) { }
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
            if let access = access {
                didModify(for: access)
            }
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
    func value<T: Equatable>(for path: KeyPath<State, T>, access: StoreAccess?) -> T {
        value(for: path, access: access, isSame: ==)
    }
}

