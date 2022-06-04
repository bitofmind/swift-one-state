import Foundation
import SwiftUI

/// Holds a model that drives SwiftUI views
///
/// A minimal view model must at least declare its state using `@ModelState`
///
///     struct MyModel: ViewModel {
///         struct State: Equatable {
///             var count = 0
///         }
///         @ModelState state: State
///     }
///
/// To access a model state and methods from a view it should be declared using `@Model`:
///
///     struct MyView: View {
///         @Model var model: MyModel
///
///         var body: some View {
///             Text("count \(model.count)")
///         }
///     }
///
/// Further a model needs to be set up from some store or a store's sub-state using `viewModel()`:
///
///     struct MyApp: App {
///         @Store<MyView> var store = .init()
///
///         var body: some Scene {
///             WindowGroup {
///                 MyView(model: $store.model)
///             }
///         }
///     }
@dynamicMemberLookup
public protocol ViewModel: ModelContainer {
    /// The type of the this view model's state.
    associatedtype State

    /// The type of events that this model can send
    associatedtype Event = ()

    init()
    
    /// Is called when when a SwiftUI view is being displayed using this model
    ///
    /// Useful for handlng the lifetime of a model and set up of longliving tasks.
    ///
    /// If more then one view is active for the same state at the same time,
    /// onAppear is only called for the first appeance and similarly any stored
    /// cancellables is cancelled not until the last view is no longer being displayed.
    @MainActor func onAppear()
}

public extension ViewModel {
    func onAppear() {}
}

public extension ViewModel {
    /// Constructs a view model with a view into a store's state
    ///
    /// A view modal is required to be constructed from a view into a store's state for
    /// its `@ModelState` and other dependencies such as `@ModelEnvironment` to be
    /// set up correclty.
    @MainActor
    init<Provider: StoreViewProvider>(_ viewStore: Provider) where Provider.State == State, Provider.Access == Write {
        let view = viewStore.storeView
        self.init(context: view.context.context(at: view.path))
    }
}

public extension ViewModel where State: Identifiable {
    typealias ID = State.ID
    
    var id: State.ID {
        let view = storeView
        return view.context[path: view.path(\.id), access: view.access]
    }
}

public extension ViewModel {
    /// Add an action to be called once the view goes away
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func onDisappear(_ perform: @escaping () -> Void) -> Cancellable {
        AnyCancellable(onCancel: perform).store(in: self)
    }

    /// Perform a task for the life time of the model
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func task(_ operation: @escaping @MainActor () async throws -> Void, `catch`: (@MainActor (Error) -> Void)? = nil) -> Cancellable {
        Task { @MainActor in
            do {
                try await context {
                    guard !Task.isCancelled else { return }
                    try await operation()
                }
            } catch {
                `catch`?(error)
            }
        }.store(in: self)
    }

    /// Iterate an async sequence for the life time of the model
    ///
    /// - Parameter catch: Called if the sequence throws an error
    /// - Parameter cancelPrevious: If true, will cancel any preciously async work initiated from`perform`.
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func forEach<S: AsyncSequence>(_ sequence: S, cancelPrevious: Bool = false, perform: @escaping @MainActor (S.Element) async throws -> Void, `catch`: (@MainActor (Error) -> Void)? = nil) -> Cancellable {
        task({
            guard cancelPrevious else {
                for try await value in sequence {
                    try await perform(value)
                }
                return
            }

            var task: Task<(), Error>?
            var caughtError: Error? = nil
            for try await value in sequence {
                guard caughtError == nil, !Task.isCancelled else { return }

                if let task = task {
                    task.cancel()
                    try? await task.value
                }

                task = Task {
                    guard !Task.isCancelled else { return }
                    do {
                        try await self.context {
                            try await perform(value)
                        }
                    } catch is CancellationError {
                    } catch {
                        caughtError = error
                        `catch`?(error)
                    }
                }
            }
        }, catch: `catch`)
    }

    /// Wait until the predicate based on the models state is fullfilled
    func waitUntil(_ predicate: @autoclosure @escaping () -> Bool) async throws {
        _ = await context.stateUpdates.first { _ in
            await context { predicate() }
        }
        try Task.checkCancellation()
    }

    /// Listen on model state changes for the life time of the model
    ///
    ///     onChange(of: $state.count) { count in
    ///
    /// - Parameter cancelPrevious: If true, will cancel any preciously async work initiated from`perform`.
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult @MainActor
    func onChange<Provider>(of provider: Provider, cancelPrevious: Bool = false, perform: @escaping @MainActor (Provider.State) async throws -> Void, `catch`: (@MainActor (Error) -> Void)? = nil) -> Cancellable where Provider: StoreViewProvider, Provider.State: Equatable {
        forEach(provider.values.dropFirst(), cancelPrevious: cancelPrevious, perform: perform, catch: `catch`)
    }
    
    /// Receive updates when a model state becomes equal to the provided `value`
    ///
    ///     onChange(of: $state.isActive, to: true) {
    ///
    /// - Parameter cancelPrevious: If true, will cancel any preciously async work initiated from`perform`.
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func onChange<Provider>(of provider: Provider, to value: Provider.State, cancelPrevious: Bool = false, perform: @escaping @MainActor () async throws -> Void, `catch`: (@MainActor (Error) -> Void)? = nil) -> Cancellable where Provider: StoreViewProvider, Provider.State: Equatable {
        forEach(provider.values.dropFirst().filter { $0 == value }.map { _ in () }, cancelPrevious: cancelPrevious, perform: perform, catch: `catch`)
    }

    /// Receive updates when a model state becomes non-nil
    ///
    /// - Parameter cancelPrevious: If true, will cancel any preciously async work initiated from`perform`.
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func onChange<Provider, T>(ofUnwrapped provider: Provider, perform: @escaping @MainActor (T) async throws -> Void, `catch`: (@MainActor (Error) -> Void)? = nil) -> Cancellable where Provider: StoreViewProvider, Provider.State == T?, T: Equatable {
        forEach(provider.values.dropFirst().compacted(), perform: perform, catch: `catch`)
    }
}

public extension ViewModel {
    /// Sends an event to self and ancestors
    func send(_ event: Event) {
        context.sendEvent(event, viewModel: self, callContext: .current)
    }

    /// Recieve events of type `modelType` from self or descendants
    ///
    ///     onEvent { (event, fromModel: MainModel) in
    ///
    ///     }
    @discardableResult @MainActor
    func onEvent<VM: ViewModel>(fromType modelType: VM.Type = VM.self, perform: @escaping @MainActor (VM.Event, VM) -> Void) -> Cancellable {
        forEach(context.events.compactMap {
            guard let event = $0.event as? VM.Event, let viewModel = $0.viewModel as? VM else { return nil }
            return (event, viewModel)
        }, perform: perform)
    }

    /// Recieve events of type `modelType` from self or descendants
    ///
    ///     onEvent(.disconnectTapped) { (fromModel: MainModel) in
    ///
    ///     }
    @discardableResult @MainActor
    func onEvent<VM: ViewModel>(_ event: VM.Event, fromType modelType: VM.Type = VM.self, perform: @escaping @MainActor (VM) -> Void) -> Cancellable where VM.Event: Equatable  {
        onEvent { (aEvent, model: VM) in
            guard aEvent == event else { return }
            perform(model)
        }
    }
}

public extension ViewModel {
    @discardableResult @MainActor
    func activate() -> Cancellable {
        retain()
        return AnyCancellable {
            context.releaseFromView()
        }
    }

    @discardableResult @MainActor
    func activate<VM: ViewModel>(_ viewModel: VM) -> Cancellable {
        viewModel.activate().store(in: self)
    }
}

public extension ViewModel {
    subscript<T: Equatable>(dynamicMember path: KeyPath<State, T>) -> T {
        value(for: path)
    }

    subscript<T: Equatable>(dynamicMember path: WritableKeyPath<State, T>) -> T {
        value(for: path)
    }

    subscript<S, T: Equatable>(dynamicMember path: WritableKeyPath<S, T>) -> T?  where State == S? {
        _ = value(for: \.self, isSame: State.hasSameStructure) // To trigger update once optional toggles
        guard let path  = nonObservableState.elementKeyPaths.first?.appending(path: path) else { return nil }
        return value(for: path)
    }

    subscript<S, T: Equatable>(dynamicMember path: WritableKeyPath<S, T?>) -> T?  where State == S? {
        _ = value(for: \.self, isSame: State.hasSameStructure) // To trigger update once optional toggles
        guard let path = nonObservableState.elementKeyPaths.first?.appending(path: path) else { return nil }
        return value(for: path)
    }

    subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, Writable<T>>) -> Binding<T> {
        let storeView = self.storeView
        return .init {
            storeView.value(for: keyPath).wrappedValue
        } set: { newValue in
            storeView.setValue(newValue, at: keyPath)
        }
    }

    var nonObservableState: State {
        let view = self.storeView
        return view.context[path: view.path, access: view.access]
    }
}

public extension ViewModel where State: Equatable {
    var value: State {
        value(for: \.self)
    }
}

public extension ViewModel {
    func value<T>(for keyPath: KeyPath<State, T>, isSame: @escaping (T, T) -> Bool) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, isSame: isSame)
    }

    func value<T: Equatable>(for keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath, isSame: ==)
    }
}

public extension ViewModel {
    func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
        let callContext = CallContext { action in
            SwiftUI.withAnimation(animation) {
                action()
            }
        }

        return try CallContext.$current.withValue(callContext) {
            try body()
        }
    }
}

public struct EmptyModel<State>: ViewModel {
    public typealias State = State
    @ModelState var state: State
    public init() {}
}

extension ViewModel {
    var storeView: StoreView<State, State, Write> {
        let modelState = self.modelState
        guard let context = modelState?.context as? Context<State> else {
            fatalError("ViewModel \(type(of: self)) is used before fully initialized")
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

extension ViewModel {
    @MainActor
    init(context: Context<State>) {
        context.propertyIndex = 0
        self = ContextBase.$current.withValue(context) {
             Self()
        }

        if context.isForTesting {
            self.retain()
        }
    }
    
    var context: Context<State> {
        guard let context = modelState?.context else {
            fatalError("ViewModel \(type(of: self)) is used before fully initialized")
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
    
    @discardableResult func context<T>(@_inheritActorContext _ operation: @escaping @MainActor @Sendable () async throws -> T) async rethrows -> T {
        try await StoreAccess.$isInViewModelContext.withValue(true) {
            try await operation()
        }
    }
}

extension ViewModel {
    @MainActor
    func retain() {
        context.retainFromView()
        guard !context.isOverrideStore, context.refCount == 1 else { return }
                
        ContextBase.$current.withValue(nil) {
            onAppear()
        }
    }
    
    func release() {
        context.releaseFromView()
    }
}
