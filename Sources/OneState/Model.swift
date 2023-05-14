import Foundation
import AsyncAlgorithms
import CustomDump
import Dependencies

/// A type that models the state and logic that drives SwiftUI views
///
/// A minimal model must at least declare its state using `@ModelState`
///
///     struct MyModel: Model {
///         struct State: Equatable {
///             var count = 0
///         }
///         @ModelState state: State
///     }
///
/// To access a model state and methods from a view it should be declared using `@ObservedModel`:
///
///     struct MyView: View {
///         @ObservedModel var model: MyModel
///
///         var body: some View {
///             Text("count \(model.count)")
///         }
///     }
///
/// Further a model needs to be set up from some store or a store's sub-state:
///
///     struct MyApp: App {
///         let store = Store<MyView>(initialState: .init())
///
///         var body: some Scene {
///             WindowGroup {
///                 MyView(model: $store.model)
///             }
///         }
///     }
@dynamicMemberLookup
public protocol Model: ModelContainer {
    /// The type of the this view model's state.
    associatedtype State

    /// The type of events that this model can send
    associatedtype Event = ()

    init()
    
    /// Will be called once the model becomes active in a store
    ///
    /// Useful for handling the lifetime of a model and set up of long-living tasks.
    /// Once the models state is removed from the store, it is deactivated and
    /// all stored cancellables are cancelled.
    ///
    /// In the typical case that a model is only used in views, `onActivate` will only
    /// be called for the first appearance and wont deactivate until the last view is no
    /// longer being displayed.
    func onActivate()
}

public extension Model {
    func onActivate() {}
}

public extension Model {
    /// Constructs a model with a view into a store's state
    ///
    /// A model is required to be constructed from a view into a store's state for
    /// its `@ModelState` and other dependencies such as `@ModelEnvironment` to be
    /// set up correctly. This  will automatically be handled when using `@StateModel`, but
    /// sometimes you might  have to manually create the model
    ///
    ///     MyModel($store.myModalState)
    init<Provider: StoreViewProvider>(_ provider: Provider) where Provider.State == State, Provider.Access == Write {
        let view = provider.storeView
        self = StoreAccess.with(view.access) {
            view.context.model(at: view.path)
        }
    }

    /// Constructs a model together with a store.
    ///
    /// Convenience initializer when working with e.g. SwiftUI previews:
    ///
    ///     struct AppView_Previews: PreviewProvider {
    ///       static var previews: some View {
    ///         AppView(model: AppModel(initialState: .init(count: 4711)) {
    ///           $0.uuid == .incrementing
    ///         }
    ///       }
    ///     }
    init(initialState: State, dependencies: @escaping (inout DependencyValues) -> Void = { _ in }) {
        self = Store<Self>(initialState: initialState, dependencies: dependencies).model
    }
}

public extension Model where State: Identifiable {
    typealias ID = State.ID
    
    var id: State.ID {
        let view = storeView
        return view.context[path: view.path(\.id), access: view.access]
    }
}

public extension Model {
    ///  Register a `perform` closure to be called when the returned `Cancellable` is canceled.
    ///  The returned `Cancellable` will be set up to cancel once the self is destructed.
    @discardableResult
    func onCancel(_ perform: @Sendable @escaping () -> Void) -> Cancellable {
        AnyCancellable(cancellations: context.cancellations) {
            perform()
        }.cancel(for: context.contextCancellationKey)
    }

    /// Cancel all cancellables that have been registered for the provided `key`
    ///
    ///     let key = UUID()
    ///
    ///     model.task {
    ///        // work...
    ///     }.cancel(for: key)
    ///
    ///     model.cancelAll(for: key)
    func cancelAll(for key: some Hashable&Sendable) {
        context.cancellations.cancelAll(for: key)
    }

    /// Cancel all cancellables that have been registered for the provided `type`
    ///
    ///     enum ID {}
    ///
    ///     model.task {
    ///        // work...
    ///     }.cancel(for: ID.self)
    ///
    ///     model.cancelAll(for: ID.self)
    func cancelAll(for id: Any.Type) {
        context.cancellations.cancelAll(for: id)
    }
}

public extension Model {
    /// Add an action to be called once the model is deactivated (same as `onCancel`)
    /// - Returns: A cancellable to optionally allow cancelling before a is deactivated
    @discardableResult
    func onDeactivate(_ perform: @Sendable @escaping () -> Void) -> Cancellable {
        onCancel(perform)
    }

    /// Perform a task for the life time of the model
    /// - Parameter priority: The priority of the  task.
    /// - Parameter operation: The operation to perform.
    /// - Parameter catch: Called if the task throws an error
    /// - Returns: A cancellable to optionally allow cancelling before deactivation.
    @discardableResult
    func task(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async throws -> Void, `catch`: @escaping @Sendable (Error) -> Void) -> Cancellable {
        if !context.assertActive(refreshContainers: true) {
            return EmptyCancellable()
        }

        return TaskCancellable(
            name: typeDescription,
            cancellations: context.cancellations,
            priority: priority,
            operation: operation,
            catch: `catch`
        )
        .cancel(for: context.contextCancellationKey)
    }

    /// Perform a task for the life time of the model
    /// - Parameter priority: The priority of the  task.
    /// - Parameter operation: The operation to perform.
    /// - Returns: A cancellable to optionally allow cancelling before deactivation.
    @discardableResult
    func task(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async -> Void) -> Cancellable {
        task(priority: priority, operation, catch: { _ in })
    }

    /// Iterate an async sequence for the life time of the model
    ///
    /// - Parameter sequence: The sequence to iterate..
    /// - Parameter cancelPrevious: If true, will cancel any preciously async work initiated from`perform`.
    /// - Parameter priority: The priority of the  task.
    /// - Parameter operation: The operation to perform for each element in the sequence.
    /// - Parameter catch: Called if the sequence throws an error
    /// - Returns: A cancellable to optionally allow cancelling before deactivation.
    @discardableResult
    func forEach<S: AsyncSequence&Sendable>(_ sequence: S, cancelPrevious: Bool = false, priority: TaskPriority? = nil, perform operation: @escaping @Sendable (S.Element) async throws -> Void, `catch`: (@Sendable (Error) -> Void)? = nil) -> Cancellable where S.Element: Sendable {
        let cancellations = context.cancellations
        let typeDescription = typeDescription
        return task(priority: priority, {
            guard cancelPrevious else {
                for try await value in sequence {
                    let streamContexts = CallContext.streamContexts.value
                    CallContext.streamContexts.value.removeAll()

                    try await CallContext.$currentContexts.withValue(streamContexts) {
                        try await operation(value)
                    }
                }
                return
            }

            let cancelID = UUID()
            try await withTaskCancellationHandler {
                for try await value in sequence {
                    let streamContexts = CallContext.streamContexts.value
                    CallContext.streamContexts.value.removeAll()

                    cancellations.cancelAll(for: cancelID)
                    TaskCancellable(
                        name: typeDescription,
                        cancellations: cancellations,
                        priority: priority,
                        operation: {
                            guard !Task.isCancelled else { return }
                            do {
                                try await inViewModelContext {
                                    try await CallContext.$currentContexts.withValue(streamContexts) {
                                        try await operation(value)
                                    }
                                }
                            } catch is CancellationError {
                                print()
                            } catch {
                                `catch`?(error)
                                throw error
                            }
                        }
                    ).cancel(for: cancelID)
                }
            } onCancel: {
                cancellations.cancelAll(for: cancelID)
            }
        }, catch: { `catch`?($0) })
    }

    /// Wait until the predicate based on the model's state is fulfilled
    func waitUntil(_ predicate: @autoclosure @escaping @Sendable () -> Bool) async throws {
        let initial = AsyncStream<()> { c in
            c.yield(())
            c.finish()
        }
        let updates = context.stateUpdates.map { _ in () }

        _ = await chain(initial, updates).first(where: predicate)
        try Task.checkCancellation()
    }
}

public struct EventReceivers: OptionSet {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let `self` = EventReceivers(rawValue: 1 << 0)
    public static let ancestors = EventReceivers(rawValue: 1 << 1)
    public static let descendants = EventReceivers(rawValue: 1 << 2)
    public static let parent = EventReceivers(rawValue: 1 << 3)
    public static let children = EventReceivers(rawValue: 1 << 4)
}

public extension Model {
    /// Sends an event.
    /// - Parameter event: even to send.
    /// - Parameter receivers: Receivers of the event, default to self and ancestors.
    func send(_ event: Event, to receivers: EventReceivers = [.self, .ancestors]) {
        let view = storeView
        context.sendEvent(event, to: receivers, context: view.context, callContexts: CallContext.currentContexts, storeAccess: view.access)
    }

    /// Sends an event.
    /// - Parameter event: even to send.
    /// - Parameter receivers: Receivers of the event, default to self and ancestors.
    func send<E>(_ event: E, to receivers: EventReceivers = [.self, .ancestors]) {
        let view = storeView
        context.sendEvent(event, to: receivers, context: view.context, callContexts: CallContext.currentContexts, storeAccess: view.access)
    }
}

public extension Model {
    /// Returns a sequence of events sent from this model.
    func events() -> AnyAsyncSequence<Event> {
        AnyAsyncSequence(context.callContextEvents.compactMap { [context] in
            guard let e = $0.event as? Event, $0.context === context else { return nil }
            return e
        })
    }

    /// Returns a sequence that emits when events of type `eventType` is sent from this model or any of its descendants.
    func events<E: Sendable>(ofType eventType: E.Type = E.self) -> AnyAsyncSequence<E> {
        AnyAsyncSequence(context.callContextEvents.compactMap {
            guard let e = $0.event as? E else { return nil }
            return e
        })
    }

    /// Returns a sequence of events sent from this model or any of its descendants.
    ///
    ///     forEach(events(fromType: ChildModel.self)) { event, model in ... }
    ///
    ///     forEach(events()) { (event, _: ChildModel) in ... }
    func events<M: Model>(fromType modelType: M.Type = M.self) -> AnyAsyncSequence<(event: M.Event, model: M)> {
        AnyAsyncSequence(context.callContextEvents.compactMap {
            guard let event = $0.event as? M.Event, let context = $0.context as? Context<M.State> else { return nil }
            return (event, M(context: context))
        })
    }

    /// Returns a sequence that emits when events of type `eventType` is sent from model or any of its descendants of the type `fromType`.
    func events<E: Sendable, M: Model>(ofType eventType: E.Type = E.self, fromType modelType: M.Type = M.self) -> AnyAsyncSequence<(event: E, model: M)> {
        AnyAsyncSequence(context.callContextEvents.compactMap {
            guard let event = $0.event as? E, let context = $0.context as? Context<M.State> else { return nil }
            return (event, M(context: context))
        })
    }
}

public extension Model {
    /// Returns a sequence that emits when events equal to the provided `event` is sent from this model.
    func events(of event: Event) -> AnyAsyncSequence<()> where Event: Equatable&Sendable {
        AnyAsyncSequence(context.callContextEvents.compactMap { [context] in
            guard let e = $0.event as? Event, e == event, $0.context === context else { return nil }
            return ()
        })
    }

    /// Returns a sequence that emits when events equal to the provided `event` is sent from this model or any of its descendants.
    func events<E: Equatable&Sendable>(of event: E) -> AnyAsyncSequence<()> {
        AnyAsyncSequence(context.callContextEvents.compactMap {
            guard let e = $0.event as? E, e == event else { return nil }
            return ()
        })
    }

    /// Returns a sequence that emits when events equal to the provided `event` is sent from this model or any of its descendants.
    ///
    ///     forEach(events(of: .someEvent, fromType: ChildModel.self)) { model in ... }
    ///
    ///     forEach(events(of: .someEvent)) { (_: ChildModel) in ... }
    func events<M: Model>(of event: M.Event, fromType modelType: M.Type = M.self) -> AnyAsyncSequence<M> where M.Event: Equatable&Sendable {
        AnyAsyncSequence(context.callContextEvents.compactMap {
            guard let e = $0.event as? M.Event, e == event, let context = $0.context as? Context<M.State> else { return nil }
            return M(context: context)
        })
    }

    /// Returns a sequence that emits when events equal to the provided `event` is sent from this model or any of its descendants of type `fromType`.
    func events<E: Equatable&Sendable, M: Model>(of event: E, fromType modelType: M.Type = M.self) -> AnyAsyncSequence<M> {
        AnyAsyncSequence(context.callContextEvents.compactMap {
            guard let e = $0.event as? E, e == event, let context = $0.context as? Context<M.State> else { return nil }
            return M(context: context)
        })
    }
}

public extension Model {
    func changes<T: Equatable&Sendable>(of path: KeyPath<State, T>) -> AnyAsyncSequence<T> {
        storeView(for: path).changes
    }

    func values<T: Equatable&Sendable>(of path: KeyPath<State, T>) -> AnyAsyncSequence<T> {
        storeView(for: path).values
    }

    @discardableResult
    func printStateUpdates<T>(of path: KeyPath<State, T>, name: String = "") -> Cancellable where T: Sendable&Equatable {
        forEach(values(of: path).adjacentPairs()) { previous, current in
            guard let diff = diff(previous, current) else { return }
            print("State did update\(name.isEmpty ? "" : " for \(name)"):\n" + diff)
        }.cancel(for: TestStoreScope.self)
    }

    @discardableResult
    func printStateUpdates(name: String = "") -> Cancellable where State: Sendable&Equatable {
        printStateUpdates(of: \.self, name: name)
    }
}

public extension Model {
    @_disfavoredOverload
    subscript<T: Equatable>(dynamicMember path: KeyPath<State, T>) -> T {
        value(for: path)
    }

    @_disfavoredOverload
    subscript<T: Equatable>(dynamicMember path: WritableKeyPath<State, T>) -> T {
        value(for: path)
    }

    subscript<S, T: Equatable>(dynamicMember path: WritableKeyPath<S, T>) -> T? where State == S? {
        _ = containerValue(for: \.self, forStateContainerType: Optional.self) // To trigger update once optional toggles
        guard let path = Optional.elementKeyPaths(for: nonObservableState).first?.appending(path: path) else { return nil }
        return value(for: path)
    }

    subscript<S, T: Equatable>(dynamicMember path: WritableKeyPath<S, T?>) -> T? where State == S? {
        _ = containerValue(for: \.self, forStateContainerType: Optional.self) // To trigger update once optional toggles
        guard let path = Optional.elementKeyPaths(for: nonObservableState).first?.appending(path: path) else { return nil }
        return value(for: path)
    }

    var nonObservableState: State {
        let view = self.storeView
        return view.context[path: view.path, access: view.access]
    }
}

public extension Model where State: Equatable {
    var value: State {
        value(for: \.self)
    }
}

public extension Model {
    func value<T: Equatable>(for path: KeyPath<State, T>) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: path), access: view.access, comparable: EquatableComparableValue.self)
    }

    func containerValue<T: OneState.StateContainer>(for path: KeyPath<State, T.Container>, forStateContainerType: T.Type = T.self) -> T.Container {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: path), access: view.access, comparable: StructureComparableValue<T>.self)
    }
}

extension Model {
    var storeView: StoreView<State, State, Write> {
        let modelState = self.modelState
        guard let context = modelState?.context as? Context<State> else {
            fatalError("Model \(type(of: self)) is used before fully initialised")
        }
        return .init(context: context, path: \.self, access: modelState?.storeAccess)
    }

    func storeView<T>(for keyPath: WritableKeyPath<State, T>) -> StoreView<State, T, Write> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }

    func storeView<T>(for keyPath: KeyPath<State, T>) -> StoreView<State, T, Read> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }

    func setValue<T>(_ value: T, at keyPath: WritableKeyPath<State, Writable<T>>) {
        let view = storeView
        return view.context[path: view.path(keyPath), access: view.access] = .init(wrappedValue: value)
    }
}

extension Model {
    init(context: Context<State>) {
        self = context.getModel()
    }
    
    var context: Context<State> {
        guard let context = modelState?.context else {
            fatalError("Model \(type(of: self)) is missing a mandatory @ModelState member")
        }

        return context
    }

    var modelState: ModelState<State>? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let state = child.value as? ModelState<State> {
                return state
            }
        }

        return nil
    }

    var typeDescription: String {
        String(describing: type(of: self))
    }
}

@discardableResult nonisolated
func inViewModelContext<T: Sendable>(@_inheritActorContext _ operation: @escaping () async throws -> T) async rethrows -> T {
    try await StoreAccess.$isInViewModelContext.withValue(true) {
        try await operation()
    }
}

@discardableResult nonisolated
func inViewModelContext<T: Sendable>(@_inheritActorContext _ operation: @escaping () throws -> T) rethrows -> T {
    try StoreAccess.$isInViewModelContext.withValue(true) {
        try operation()
    }
}
