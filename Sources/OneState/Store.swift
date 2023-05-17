import Foundation
import Dependencies

/// A store holds the state of an application or part of a application
///
/// From its state or a sub-state of that state, models are instantiated to maintain
/// the state and drive the refreshes of SwiftUI views
///
/// Typically you set up you store in your app's scene:
///
///     struct MyApp: App {
///         let store = Store<AppView>(initialState: .init())
///
///         var body: some Scene {
///             WindowGroup {
///                 AppViewView(model: store.model)
///             }
///         }
///     }
///
/// You can override default dependencies via the `dependencies` closure callback:
///
///     Store<AppView>(initialState: .init()) {
///         $0.uuid = .incrementing
///     }
///
@dynamicMemberLookup
public final class Store<Models: ModelContainer>: @unchecked Sendable {
    public typealias State = Models.Container

    let internalStore: InternalStore<Models>
    let context: ChildContext<Models, Models>

    private init(internalStore: InternalStore<Models>) {
        self.internalStore = internalStore
        self.context = ChildContext<Models, Models>(store: internalStore, path: \.self, parent: nil)
    }
}

public extension Store {
    /// Creates a store.
    ///
    ///     Store<AppView>(initialState: .init()) {
    ///        $0.uuid = .incrementing
    ///        $0.locale = Locale(identifier: "en_US")
    ///     }
    ///
    /// - Parameter initialState:The store's initial state.
    /// - Parameter dependencies: The overridden dependencies of the store.
    ///
    convenience init(initialState: State, dependencies: @escaping (inout DependencyValues) -> Void = { _ in }) {
        self.init(internalStore: InternalStore(initialState: initialState, dependencies: dependencies))
    }

    var model: Models {
        Models(self)
    }

    var state: State {
        internalStore.state
    }

    /// Used to override state when replaying recorded state
    var stateOverride: State? {
        get { internalStore.stateOverride }
        set {
            internalStore.stateOverride = newValue
            context.notify(StateUpdate(isStateOverridden: true, isOverrideUpdate: true, fromContext: context))
        }
    }
}

public extension Store where Models.StateContainer: DefaultedStateContainer {
    /// Creates a store.
    ///
    ///     Store<AppView?> {
    ///       $0.uuid = .incrementing
    ///
    ///       return await loadInitialState()
    ///     }
    ///
    /// - Parameter delayedInitialState:A async closure passing overridden dependencies of the store and returning the initial state.
    ///
    convenience init(delayedInitialState: @escaping (inout DependencyValues) async -> State) {
        self.init(internalStore: InternalStore(initialState: Models.StateContainer.defaultContainer(), dependencies: { _ in }))
        Task {
            await self.internalStore.delayedInitialState {
                (self.context, await delayedInitialState(&$0))
            }
        }
    }
}

extension Store: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: nil)
    }
}

import Combine

extension Store: ObservableObject {
    public var objectWillChange: ObservableObjectPublisher {internalStore.objectWillChange }
}

