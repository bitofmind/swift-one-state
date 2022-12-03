import AsyncAlgorithms
import CustomDump

/// Conforming types exposes a view into the store holding its state
///
/// Typically conforming types are also declared as `@dynamicMemberLookup`
/// to allow convienent access to a stores states members.
///
/// Most common when accessing a sub state is that you get anothter store view
/// back instead of the raw value. This allows you to construct viewModels with direct
/// view into a store:
///
///     MyModel(provider.myState)
public protocol StoreViewProvider {
    associatedtype Root
    associatedtype State
    associatedtype Access

    var storeView: StoreView<Root, State, Access> { get }
}

public extension StoreViewProvider where State: Sendable {
    func changes(isSame: @escaping @Sendable (State, State) -> Bool) -> CallContextsStream<State> {
        CallContextsStream(allChanges().stream.removeDuplicates {
            isSame($0.value, $1.value)
        })
    }

    func values(isSame: @escaping @Sendable (State, State) -> Bool) -> CallContextsStream<State> {
        let state = AsyncStream<WithCallContexts<State>> { c in
            c.yield(.init(value: nonObservableState, callContexts: []))
            c.finish()
        }
        let changes = changes(isSame: isSame)
        return CallContextsStream(chain(state, changes.stream).removeDuplicates {
            isSame($0.value, $1.value)
        })
    }
}

public extension StoreViewProvider where State: Equatable&Sendable {
    var changes: CallContextsStream<State> {
        changes(isSame: { $0 == $1 })
    }

    var values: CallContextsStream<State> {
        values(isSame: { $0 == $1 })
    }
}

public extension StoreViewProvider {
    func value<T>(for keyPath: KeyPath<State, T>, isSame: @escaping (T, T) -> Bool) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, isSame: isSame, ignoreChildUpdates: false)
    }

    func value<T: Equatable>(for keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath, isSame: ==)
    }
}

public extension StoreViewProvider {
    func storeView<T>(for keyPath: KeyPath<State, T>) -> StoreView<Root, T, Read> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }
}

public extension StoreViewProvider where Access == Write {
    func storeView<T>(for keyPath: WritableKeyPath<State, T>) -> StoreView<Root, T, Write> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }

    func setValue<T>(_ value: T, at keyPath: WritableKeyPath<State, Writable<T>>) {
        let view = storeView
        return view.context[path: view.path(keyPath), access: view.access] = .init(wrappedValue: value)
    }
}

public extension StoreViewProvider {
    subscript<T>(dynamicMember path: KeyPath<State, T>) -> StoreView<Root, T, Read> {
        storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: KeyPath<S, T>) -> StoreView<Root, T?, Read> where State == S? {
        let view = storeView
        let unwrapPath = view.path.appending(path: \.[unwrap: path])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }

    subscript<S, T>(dynamicMember path: KeyPath<S, T?>) -> StoreView<Root, T?, Read> where State == S? {
        let view = storeView
        let unwrapPath = view.path.appending(path: \.[unwrap: path])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }

    subscript<T>(dynamicMember path: KeyPath<State, T?>) -> StoreView<Root, T, Read>? {
        storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: KeyPath<S, T>) -> StoreView<Root, T, Read>? where State == S? {
        storeView(for: \.self)?.storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: KeyPath<S, T?>) -> StoreView<Root, T, Read>? where State == S? {
        storeView(for: \.self)?.storeView(for: path)
    }
}

public extension StoreViewProvider where Access == Write {
    subscript<T>(dynamicMember path: WritableKeyPath<State, T>) -> StoreView<Root, T, Write> {
        storeView(for: path)
    }

    subscript<Models>(dynamicMember path: WritableKeyPath<State, StateModel<Models>>) -> StoreView<Root, StateModel<Models>, Write> where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        observeContainer(atPath: path)
        return storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: WritableKeyPath<S, T>) -> StoreView<Root, T?, Write> where State == S? {
        let view = storeView
        let unwrapPath = view.path.appending(path: \.[unwrap: path])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }

    subscript<S, T>(dynamicMember path: WritableKeyPath<S, T?>) -> StoreView<Root, T?, Write> where State == S? {
        let view = storeView
        let unwrapPath = view.path.appending(path: \.[unwrap: path])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }

    subscript<T>(dynamicMember path: WritableKeyPath<State, T?>) -> StoreView<Root, T, Write>? {
        storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: WritableKeyPath<S, T>) -> StoreView<Root, T, Write>? where State == S? {
        storeView(for: \.self)?.storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: WritableKeyPath<S, T?>) -> StoreView<Root, T, Write>? where State == S? {
        storeView(for: \.self)?.storeView(for: path)
    }
}

public extension StoreViewProvider {
    func printStateUpdates(name: String = "") where State: Sendable {
        let stateUpdates = stateUpdates
        Task {
            for await update in stateUpdates {
                update.printDiff(name: name)
            }
        }
    }
}

extension StoreViewProvider {
    var nonObservableState: State {
        let view = self.storeView
        return view.context[path: view.path, access: view.access]
    }

    func allChanges() -> CallContextsStream<State> {
        let view = self.storeView
        return CallContextsStream(view.context.stateUpdates.map { stateChange -> WithCallContexts<State> in
            let stateUpdate = StateUpdate(stateChange: stateChange, provider: view)
            let current = stateUpdate.current

            return WithCallContexts(value: current, callContexts: stateChange.callContexts)
        })
    }
}

extension StoreViewProvider where Access == Write {
    func observeContainer<Models>(atPath path: WritableKeyPath<State, StateModel<Models>>) where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let view = storeView
        let containerPath = view.path.appending(path: path).appending(path: \.wrappedValue)
        let context = view.context
        if context.containers[containerPath] == nil {
            context.containers[containerPath] = { update in
                let prevContainer = view.context[path: containerPath, shared: update.previous]
                let currentContainer = view.context[path: containerPath, shared: update.current]

                guard !Models.StateContainer.hasSameStructure(lhs: prevContainer, rhs: currentContainer) else {
                    return
                }

                let prevElementPaths = Set(prevContainer.elementKeyPaths)
                let currentElementPaths = Set(currentContainer.elementKeyPaths)

                let addedPaths = currentElementPaths.subtracting(prevElementPaths)
                let removedPaths = prevElementPaths.subtracting(currentElementPaths)

                for addedPath in addedPaths {
                    let childPath = containerPath.appending(path: addedPath)
                    if context.allChildren[childPath] == nil {
                        let containerView = StoreView(context: view.context, path: childPath, access: nil)
                        _ = Models.ModelElement(containerView)
                    }
                }

                for removedPath in removedPaths {
                    if let childContext = context.allChildren[containerPath.appending(path: removedPath)] {
                        childContext.removeRecusively()
                    }
                }
            }
        }
    }
}

private extension Optional {
    subscript<T> (unwrap path: KeyPath<Wrapped, T>) -> T? {
        self?[keyPath: path]
    }

    subscript<T> (unwrap path: KeyPath<Wrapped, T?>) -> T? {
        self?[keyPath: path]
    }

    subscript<T> (unwrap path: WritableKeyPath<Wrapped, T>) -> T? {
        get {
            self?[keyPath: path]
        }
        set {
            if let value = newValue {
                self?[keyPath: path] = value
            }
        }
    }

    subscript<T> (unwrap path: WritableKeyPath<Wrapped, T?>) -> T? {
        get {
            self?[keyPath: path]
        }
        set {
            self?[keyPath: path] = newValue
        }
    }
}
