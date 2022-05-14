import Foundation
import Combine

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
public protocol ViewModel: ModelContainer, StoreViewProvider {
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
    func onAppear()
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
    init<Provider: StoreViewProvider>(_ viewStore: Provider) where Provider.State == State {
        let view = viewStore.storeView
        let context = view.context.context(at: view.path)

        context.propertyIndex = 0
        self = ContextBase.$current.withValue(context) {
             Self()
        }

        if context.isForTesting {
            self.retain()
        }
    }
}

public extension ViewModel {
    /// Conformance to `StoreViewProvider`
    var storeView: StoreView<State, State> {
        .init(context: context, path: \.self, access: .fromView)
    }
}

public extension ViewModel where State: Identifiable {
    typealias ID = State.ID
    
    var id: State.ID {
        let view = storeView
        return view.context[keyPath: view.path(\.id), access: view.access]
    }
}

public extension Cancellable {
    /// Cancellables stored in a view model will be cancelled once the last view using the model for the
    /// same underlying state is non longer being displayed
    func store<VM: ViewModel>(in viewModel: VM) {
        store(in: &viewModel.context.anyCancellables)
    }
}

public extension ViewModel {
    /// Add an action to be called once the view goes away
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func onDisappear(_ perform: @escaping () -> Void) -> AnyCancellable {
        let cancellable = AnyCancellable(perform)
        cancellable.store(in: self)
        return cancellable
    }

    /// Perform a task for the life time of the model
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult func task(_ operation: @escaping @MainActor () async throws -> Void, `catch`: ((Error) -> Void)? = nil) -> AnyCancellable {
        let task = Task {
            do {
                try await context {
                    guard !Task.isCancelled else { return }
                    try await operation()
                }
            } catch {
                `catch`?(error)
            }
        }
        
        return onDisappear(task.cancel)
    }

    /// Iterate an async sequence for the life time of the model
    ///
    /// - Parameter catch: Called if the sequence throws an error
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult func forEach<S: AsyncSequence>(_ sequence: S, perform: @escaping @MainActor (S.Element) async throws -> Void, `catch`: ((Error) -> Void)? = nil) -> AnyCancellable {
        task({
            for try await value in sequence {
                try await perform(value)
            }
        }, catch: `catch`)
    }
    
    /// Receive updates from a publisher for the life time of the model
    ///
    /// - Parameter catch: Called if the sequence throws an error
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult func onReceive<P: Publisher>(_ publisher: P, perform: @escaping @MainActor (P.Output) async throws -> Void, `catch`: ((Error) -> Void)? = nil) -> AnyCancellable {
        if #available(iOS 15, macOS 12,  *) {
            return forEach(publisher.values, perform: perform, catch: `catch`)
        } else {
            let stream = AsyncStream<P.Output> { cont in
                let cancellable = publisher.sink(receiveCompletion: { completion in
                    if case let .failure(error) = completion {
                        `catch`?(error)
                    }
                      
                    cont.finish()
                }, receiveValue: { value in
                    cont.yield(value)
                })
                
                cont.onTermination = { _ in
                    cancellable.cancel()
                }
            }

            return forEach(stream, perform: perform, catch: `catch`)
        }
    }

    /// Wait until the predicate based on the models state is fullfilled
    @available(iOS 15, macOS 12,  *)
    func waitUntil(_ predicate: @autoclosure @escaping () -> Bool) async {
        _ = await context.stateDidUpdate.values.first { _ in
            await context { predicate() }
        }
    }
    
    /// Listen on model state changes for the life time of the model
    ///
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult func onChange<T: Equatable>(of keyPath: KeyPath<State, T>, perform: @escaping (T) -> Void) -> AnyCancellable {
        onReceive(stateDidUpdatePublisher) { change in
            guard let value = change[dynamicMember: keyPath] else { return }
            perform(value)
        }
    }
    
    /// Receive updates when a model state becomes equal to the provided `value`
    ///
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult func onChange<T: Equatable>(of keyPath: KeyPath<State, T>, to value: T, perform: @escaping @MainActor () async throws -> Void) -> AnyCancellable {
        onReceive(stateDidUpdatePublisher) { change in
            guard let val = change[dynamicMember: keyPath], val == value else { return }
            try await perform()
        }
    }

    /// Receive updates when a model state becomes non-nil
    ///
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult func onChange<T: Equatable>(ofUnwrapped keyPath: KeyPath<State, T?>, perform: @escaping @MainActor (T) async throws -> Void) -> AnyCancellable {
        onReceive(stateDidUpdatePublisher) { update in
            guard let value = update[dynamicMember: keyPath],
                let unwrapped = value else { return }
            try await perform(unwrapped)
        }
    }
}

public extension ViewModel {
    /// Sends an event to self and ancestors
    func send(_ event: Event) {
        context.sendEvent(event, viewModel: self)
    }

    /// Recieve events of type `eventType` from self or descendants
    @discardableResult
    func onEvent<VM: ViewModel>(ofType eventType: VM.Type = VM.self, perform: @escaping (VM.Event, VM) -> Void) -> AnyCancellable {
        onReceive(context.eventSubject.compactMap {
            guard let event = $0.event as? VM.Event, let viewModel = $0.viewModel as? VM else { return nil }
            return (event, viewModel)
        }, perform: perform)
    }
}

extension ViewModel {
    var context: Context<State> {
        guard let context = rawStore else {
            fatalError("ViewModel \(type(of: self)) is used before fully initialized")
        }
        
        return context
    }
    
    var rawStore: Context<State>? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let state = child.value as? ModelState<State> {
                return state.context
            }
        }
        
        return nil
    }
    
    @discardableResult func context<T>(@_inheritActorContext _ operation: @escaping @MainActor @Sendable () async throws -> T) async rethrows -> T {
        try await StoreAccess.$viewModel.withValue(.fromViewModel) {
            try await operation()
        }
    }
}

extension StoreAccess {
    @TaskLocal static var viewModel: StoreAccess?
}

extension ViewModel {
    func retain() {
        context.retainFromView()
        guard !context.isOverrideStore, context.refCount == 1 else { return }
                
        ContextBase.$current.withValue(nil) {
            StoreAccess.$viewModel.withValue(.fromViewModel) {
                onAppear()
            }
        }
    }
    
    func release() {
        context.releaseFromView()
    }
}
