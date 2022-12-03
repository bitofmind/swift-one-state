import Foundation
import AsyncAlgorithms

/// Holds a model that drives SwiftUI views
///
/// A minimal  model must at least declare its state using `@ModelState`
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
    
    /// Is called when model is being activate
    ///
    /// Useful for handlng the lifetime of a model and set up of longliving tasks.
    ///
    /// If more then one view is active for the same state at the same time,
    /// onActivate is only called for the first appeance and similarly any stored
    /// cancellables is cancelled not until the last view is no longer being displayed.
    func onActivate()
}

public extension Model {
    func onActivate() {}
}

public extension Model {
    /// Constructs a model with a view into a store's state
    ///
    /// A view modal is required to be constructed from a view into a store's state for
    /// its `@ModelState` and other dependencies such as `@ModelEnvironment` to be
    /// set up correclty.
    init<Provider: StoreViewProvider>(_ viewStore: Provider) where Provider.State == State, Provider.Access == Write {
        let view = viewStore.storeView
        self = view.context.model(at: view.path)
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
    @discardableResult
    func onCancel(_ perform: @Sendable @escaping () -> Void) -> Cancellable {
        AnyCancellable(cancellations: context.cancellations) {
            perform()
        }.cancel(for: context.contextCancellationKey)
    }

    func cancelAll(for key: some Hashable&Sendable) {
        context.cancellations.cancelAll(for: key)
    }

    func cancelAll(for id: Any.Type) {
        context.cancellations.cancelAll(for: ObjectIdentifier(id))
    }
}

public extension Model {
    /// Add an action to be called once the model is deactivated
    /// - Returns: A cancellable to optionally allow cancelling before a is deactivated
    @discardableResult
    func onDeactivate(_ perform: @Sendable @escaping () -> Void) -> Cancellable {
        onCancel(perform)
    }

    /// Perform a task for the life time of the model
    /// - Returns: A cancellable to optionally allow cancelling before a is deactivated
    @discardableResult
    func task(priority: TaskPriority? = nil, _ operation: @escaping @Sendable () async throws -> Void, `catch`: (@Sendable (Error) -> Void)? = nil) -> Cancellable {
        TaskCancellable(
            name: typeDescription,
            cancellations: context.cancellations,
            priority: priority,
            operation: operation,
            catch: `catch`
        )
        .cancel(for: context.contextCancellationKey)
    }

    /// Iterate an async sequence for the life time of the model
    ///
    /// - Parameter catch: Called if the sequence throws an error
    /// - Parameter cancelPrevious: If true, will cancel any preciously async work initiated from`perform`.
    /// - Returns: A cancellable to optionally allow cancelling before a is deactivated
    @discardableResult
    func forEach<S: AsyncSequence&Sendable>(_ sequence: S, cancelPrevious: Bool = false, priority: TaskPriority? = nil, perform: @escaping @Sendable (S.Element) async throws -> Void, `catch`: (@Sendable (Error) -> Void)? = nil) -> Cancellable where S.Element: Sendable {
        let cancellations = context.cancellations
        let typeDescription = typeDescription
        return task(priority: priority, {
            guard cancelPrevious else {
                for try await value in sequence {
                    try await perform(value)
                }
                return
            }

            let cancelID = UUID()
            try await withTaskCancellationHandler {
                for try await value in sequence {
                    cancellations.cancelAll(for: cancelID)
                    TaskCancellable(
                        name: typeDescription,
                        cancellations: cancellations,
                        priority: priority,
                        operation: {
                            guard !Task.isCancelled else { return }
                            do {
                                try await inViewModelContext {
                                    try await perform(value)
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
        }, catch: `catch`)
    }

    @discardableResult
    func forEach<Element: Sendable>(_ sequence: CallContextsStream<Element>, cancelPrevious: Bool = false, priority: TaskPriority? = nil, perform: @escaping @Sendable (Element) async throws -> Void, `catch`: (@Sendable (Error) -> Void)? = nil) -> Cancellable {
        forEach(sequence.stream.map { ($0.value, $0.callContexts) }, cancelPrevious: cancelPrevious, priority: priority, perform: { value, callContexts in
            try await CallContext.$currentContexts.withValue(callContexts) {
                try await perform(value)
            }
        }, catch: `catch`)
    }

    /// Wait until the predicate based on the models state is fullfilled
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

public extension Model {
    /// Sends an event to self and ancestors
    func send(_ event: Event) {
        let view = storeView
        context.sendEvent(event, context: view.context, callContexts: CallContext.currentContexts, storeAccess: view.access)
    }

    /// Sends an event to self and ancestors
    func send<E>(_ event: E) {
        let view = storeView
        context.sendEvent(event, context: view.context, callContexts: CallContext.currentContexts, storeAccess: view.access)
    }

    func events() -> CallContextsStream<Event> {
        let events = context.events
        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? Event else { return nil }
            return .init(value: e, callContexts: $0.callContexts)
        })
    }

    func events(of event: Event) -> CallContextsStream<()> where Event: Equatable&Sendable {
        let events = context.events
        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? Event, e == event else { return nil }
            return .init(value: (), callContexts: $0.callContexts)
        })
    }

    func events<E: Equatable&Sendable>(of event: E) -> CallContextsStream<()> {
        let events = context.events
        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? E, e == event else { return nil }
            return .init(value: (), callContexts: $0.callContexts)
        })
    }

    func events<M: Model>(fromType modelType: M.Type = M.self) -> CallContextsStream<(event: M.Event, model: M)> {
        let events = context.events
        return CallContextsStream(events.compactMap {
            guard let event = $0.event as? M.Event, let context = $0.context as? Context<M.State> else { return nil }
            return .init(value: (event, M(context: context)), callContexts: $0.callContexts)
        })
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
        _ = value(for: \.self, isSame: State.hasSameStructure) // To trigger update once optional toggles
        guard let path = nonObservableState.elementKeyPaths.first?.appending(path: path) else { return nil }
        return value(for: path)
    }

    subscript<S, T: Equatable>(dynamicMember path: WritableKeyPath<S, T?>) -> T? where State == S? {
        _ = value(for: \.self, isSame: State.hasSameStructure) // To trigger update once optional toggles
        guard let path = nonObservableState.elementKeyPaths.first?.appending(path: path) else { return nil }
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
    func value<T>(for path: KeyPath<State, T>, isSame: @escaping (T, T) -> Bool) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: path), access: view.access, isSame: isSame, ignoreChildUpdates: false)
    }

    func value<T: Equatable>(for path: KeyPath<State, T>) -> T {
        value(for: path, isSame: ==)
    }
}

extension Model {
    var storeView: StoreView<State, State, Write> {
        let modelState = self.modelState
        guard let context = modelState?.context as? Context<State> else {
            fatalError("Model \(type(of: self)) is used before fully initialized")
        }
        return .init(context: context, path: \.self, access: modelState?.storeAccess)
    }

    func storeView<T>(for keyPath: WritableKeyPath<State, T>) -> StoreView<State, T, Write> {
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
