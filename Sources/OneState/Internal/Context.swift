class Context<State>: ContextBase {
    subscript<T> (path path: KeyPath<State, T>) -> T {
        _read { fatalError() }
    }

    subscript<T> (path path: WritableKeyPath<State, T>) -> T {
        _read { fatalError() }
        _modify { fatalError() }
    }

    subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read { fatalError() }
    }

    func storePath<StoreState, T>(for path: WritableKeyPath<State, T>) -> WritableKeyPath<StoreState, T>? {
        fatalError()
    }

    func value<Comparable: ComparableValue>(for path: KeyPath<State, Comparable.Value>, access: StoreAccess?, comparable: Comparable.Type) -> Comparable.Value {
        fatalError()
    }

    func model<M: ModelContainer>(at path: WritableKeyPath<State, M.Container>) -> M { fatalError() }

    func sendEvent(_ event: Any, to receivers: EventReceivers, context: ContextBase, callContexts: [CallContext], storeAccess: StoreAccess?) {
        let eventInfo = EventInfo(event: event, path: storePath, context: context, callContexts: callContexts)
        sendEvent(eventInfo, to: receivers)
        storeAccess?.didSend(event: eventInfo)
    }

    func didModify(for access: StoreAccess) { }

    func getModel<M: Model>() -> M { fatalError() }
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
        value(for: path, access: access, comparable: EquatableComparableValue.self)
    }
}

