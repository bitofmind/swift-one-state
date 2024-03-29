import Foundation
import AsyncAlgorithms
import CustomDump

/// Conforming types exposes a view into the store holding its state
///
/// Typically conforming types are also declared as `@dynamicMemberLookup`
/// to allow convenient access to a stores states members.
///
/// Most common when accessing a sub state is that you get another store view
/// back instead of the raw value. This allows you to construct viewModels with direct
/// view into a store:
///
///     MyModel(provider.myState)
public protocol StoreViewProvider<State, Access> {
    associatedtype Root
    associatedtype State
    associatedtype Access

    var storeView: StoreView<Root, State, Access> { get }
}

public extension StoreViewProvider {
    var stateDidUpdate: AsyncStream<()> {
        let context = self.storeView.context
        return .init(context.stateUpdates.filter { update in
            !update.isOverrideUpdate
        }.map { _ in
            _ = context // Capture context
        })
    }
}

public extension StoreViewProvider where State: Sendable {
    func changes(isSame: @escaping @Sendable (State, State) -> Bool) -> AsyncStream<State> {
        AsyncStream(values(isSame: isSame).dropFirst())
    }

    func values(isSame: @escaping @Sendable (State, State) -> Bool) -> AsyncStream<State> {
        let view = self.storeView
        return AsyncStream<State> { c in
            let value = nonObservableState
            c.yield(value)

            let task = Task {
                var prevValue = value
                for await _ in view.context.stateUpdates {
                    let value = nonObservableState
                    if !isSame(prevValue, value) {
                        c.yield(value)
                        prevValue = value
                    }
                }
            }

            c.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

public extension StoreViewProvider where State: Equatable&Sendable {
    var changes: AsyncStream<State> {
        changes(isSame: { $0 == $1 })
    }

    var values: AsyncStream<State> {
        values(isSame: { $0 == $1 })
    }
}

public extension StoreViewProvider {
    func containerValue<T: MutableCollection>(for keyPath: KeyPath<State, T>) -> T where T.Element: Identifiable {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, comparable: IDCollectionComparableValue.self)
    }

    func containerValue<T: StateContainer>(for keyPath: KeyPath<State, T.Container>, forStateContainerType: T.Type = T.self) -> T.Container {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, comparable: StructureComparableValue<T>.self)
    }

    func value<T: Equatable>(for keyPath: KeyPath<State, T>) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, comparable: EquatableComparableValue.self)
    }
}

public extension StoreViewProvider where Access == Write {
    func setValue<T>(_ value: T, at keyPath: WritableKeyPath<State, Writable<T>>) {
        let view = storeView
        guard !view.context.isOverrideContext else { return }
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
}

public extension StoreViewProvider where Access == Write {
    subscript<T>(dynamicMember path: WritableKeyPath<State, T>) -> StoreView<Root, T, Write> {
        storeView(for: path)
    }
}

extension StoreViewProvider {
    func storeView<T>(for keyPath: KeyPath<State, T>) -> StoreView<Root, T, Read> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }
}

extension StoreViewProvider where Access == Write {
    func storeView<T>(for keyPath: WritableKeyPath<State, T>) -> StoreView<Root, T, Write> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }
}

extension StoreViewProvider {
    var nonObservableState: State {
        let view = self.storeView
        return view.context[path: view.path, access: view.access]
    }

    func allChanges() -> AsyncStream<State> {
        let view = self.storeView
        return AsyncStream(view.context.stateUpdates.map { _ in
            view.nonObservableState
        })
    }
}

extension StoreViewProvider where Access == Write {
    func observeContainer<Models: ModelContainer>(ofType: Models.Type, atPath path: WritableKeyPath<State, Models.Container>) {
        let view = storeView
        let containerPath = view.path.appending(path: path)
        let context = view.context
        if context.containers[containerPath] == nil {
            let prevContainer = view.context[path: containerPath]
            let lock = NSLock()
            var prevStructure = StructureComparableValue<Models.StateContainer>(value: prevContainer)
            var prevElementPaths = Set(Models.StateContainer.elementKeyPaths(for: prevContainer))
            context.containers[containerPath] = { [weak context, weak containerContext = view.context] in
                typealias Path = WritableKeyPath<Models.StateContainer.Container, Models.ModelElement.State>

                guard let context, let containerContext else { return }

                let (addedPaths, removedPaths): (Set<Path>, Set<Path>) = lock {
                    let currentContainer = containerContext[path: containerPath]
                    let currentStructure = StructureComparableValue<Models.StateContainer>(value: currentContainer)

                    guard prevStructure != currentStructure else {
                        return (([], []))
                    }

                    let currentElementPaths = Set(Models.StateContainer.elementKeyPaths(for: currentContainer))

                    defer {
                        prevStructure = currentStructure
                        prevElementPaths = currentElementPaths
                    }

                    let addedPaths = currentElementPaths.subtracting(prevElementPaths)
                    let removedPaths = prevElementPaths.subtracting(currentElementPaths)
                    return (addedPaths, removedPaths)
                }

                for addedPath in addedPaths {
                    let childPath = containerPath.appending(path: addedPath)
                    if context.allChildren[childPath] == nil {
                        let containerView = StoreView(context: containerContext, path: childPath, access: nil)
                        _ = Models.ModelElement(containerView)
                    }
                }

                for removedPath in removedPaths {
                    if let childContext = context.allChildren[containerPath.appending(path: removedPath)] {
                        childContext.removeRecursively()
                    }
                }
            }
        }
    }

    func observeContainer<Models>(atPath path: WritableKeyPath<State, StateModel<Models>>) {
        observeContainer(ofType: Models.self, atPath: path.appending(path: \.wrappedValue))
    }
}
