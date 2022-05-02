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

///
/// Further a model needs to be set up from some store or a store's sub-state using `viewModel()`:
///
///     struct MyApp: App {
///         @Store var store = MyView.State()
///
///         var body: some Scene {
///             WindowGroup {
///                 MyView(model: $store.viewModel(MyModel()))
///             }
///         }
///     }
@dynamicMemberLookup
public protocol ViewModel: StoreViewProvider {
    /// The type of the this view model's state.
    associatedtype State
    
    /// Is called when when a SwiftUI view is being displayed using this model
    ///
    /// Useful for handlng the lifetime of a model and set up of longliving tasks.
    ///
    /// If more then one view is active for the same state at the same time,
    /// onAppear is only called for the first appeance and similarly any stored
    /// cancellables is cancelled not until the last view is no longer beeing displayed.
    func onAppear() async
}

public extension ViewModel {
    func onAppear() async {}
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
