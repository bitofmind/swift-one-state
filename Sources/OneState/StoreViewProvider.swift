import AsyncAlgorithms

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
    func values(isSame: @escaping @Sendable (State, State) -> Bool) -> AsyncStream<State> {
        let state = nonObservableState
        let changes = changes(isSame: isSame)
        return AsyncStream(chain([state].async, changes))
    }

    func changes(isSame: @escaping @Sendable (State, State) -> Bool) -> AsyncStream<State> {
        let view = self.storeView
        return AsyncStream(view.context.stateUpdates.compactMap { stateChange -> State? in
            let stateUpdate = StateUpdate(stateChange: stateChange, provider: view)

            let current = stateUpdate.current
            let previous = stateUpdate.previous

            return !isSame(previous, current) ? current : nil
        })
    }
}

public extension StoreViewProvider where State: Equatable&Sendable {
    var values: AsyncStream<State> {
        values(isSame: { $0 == $1 })
    }

    var changes: AsyncStream<State> {
        changes(isSame: { $0 == $1 })
    }
}

public extension StoreViewProvider {
    func value<T>(for keyPath: KeyPath<State, T>, isSame: @escaping (T, T) -> Bool) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, isSame: isSame)
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
}

extension StoreViewProvider {
    var nonObservableState: State {
        let view = self.storeView
        return view.context[path: view.path, access: view.access]
    }
}
