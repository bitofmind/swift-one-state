import Foundation
import Dependencies
import SwiftUI

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
public final class Store<Models: ModelContainer>: ObservableObject, @unchecked Sendable {
    public typealias State = Models.Container

    @Dependency(\.uuid) private var dependencies
    private let lock = NSRecursiveLock()

    private var currentState: State
    private var modifyCount = 0
    private var overrideState: State?
    private var overrideSinkState: State

    private var updateTask: Task<(), Never>?
    private var lastFromContext: ContextBase?
    private var lastCallContexts: [CallContext] = []

    private(set) weak var weakContext: ChildContext<Models, Models>?
    private var hasBeenActivated = false

    let cancellations = Cancellations()
    private var didStructureUpdate: (Models.StateContainer.StructureValue) -> Bool = { _ in false }

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
    public init(initialState: State, dependencies: @escaping (inout DependencyValues) -> Void = { _ in }) {
        currentState = initialState
        overrideSinkState = initialState
        withDependencies(from: self) {
            dependencies(&$0)
        } operation: {
            _dependencies = Dependency(\.uuid)
        }
    }
}

public extension Store {
    var model: Models {
        Models(self)
    }

    var state: State {
        _read {
            lock.lock()
            yield currentState
            lock.unlock()
        }
    }

    /// Used to override state when replaying recorded state
    var stateOverride: State? {
        get { lock { overrideState } }
        set {
            lock { overrideState = newValue }
            weakContext?.notify(StateUpdate(isStateOverridden: true, isOverrideUpdate: true, fromContext: context))
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
        let initialState = Models.StateContainer.defaultContainer()
        self.init(initialState: initialState) { _ in }
        var lastStructure = Models.StateContainer.structureValue(for: initialState)
        self.didStructureUpdate = { newStructure in
            if newStructure != lastStructure {
                lastStructure = newStructure
                return true
            }
            return false

        }
        Task {
            await withDependencies(from: self) {
                self[path: \.self, fromContext: context] = await delayedInitialState(&$0)
            } operation: {
                _dependencies = Dependency(\.uuid)
            }
        }
    }
}

extension Store {
    subscript<T> (path path: KeyPath<State, T>) -> T {
        _read {
            lock.lock()
            yield currentState[keyPath: path]
            lock.unlock()
        }
    }

    subscript<T> (path path: WritableKeyPath<State, T>, fromContext fromContext: ContextBase) -> T {
        _read {
            lock.lock()
            yield currentState[keyPath: path]
            lock.unlock()
        }
        _modify {
            let isOverrideContext = fromContext.isOverrideContext
            lock.lock()

            if stateOverride != nil, isOverrideContext {
                // Not allowed to modify state on an overridden store
                yield &overrideSinkState[keyPath: path]
                lock.unlock()
                return
            }

            let callContexts = CallContext.currentContexts

            var flushNotify: (() -> Void)?
            if let last = lastFromContext, (last !== fromContext || lastCallContexts != callContexts) {
                updateTask?.cancel()
                flushNotify = notifier(context: last, callContexts: lastCallContexts)
                updateTask = nil
            }

            yield &currentState[keyPath: path]
            lastFromContext = fromContext
            lastCallContexts = callContexts
            modifyCount &+= 1

            if updateTask == nil {
                // Try to coalesce updates
                updateTask = Task(priority: .medium) {
                    var waitTime: UInt64 = 0
                    while true {
                        let count = self.lock { self.modifyCount }
                        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC*10)
                        waitTime += NSEC_PER_MSEC*10

                        let shouldBreak = self.lock {
                            guard count == self.modifyCount || waitTime >= NSEC_PER_MSEC*100 else { return false }
                            guard !Task.isCancelled else { return true }
                            self.updateTask = nil
                            let notifier = self.notifier(context: fromContext, callContexts: callContexts)
                            self.lock.unlock()
                            notifier?()
                            self.lock.lock()
                            return true
                        }
                        
                        if shouldBreak { break }
                    }
                }
            }
            
            lock.unlock()
            flushNotify?()
        }
    }

    subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read {
            lock.lock()
            if let stateOverride {
                yield stateOverride[keyPath: path]
            } else {
                yield nil
            }
            lock.unlock()
        }
    }

    func notifier(context: ContextBase, callContexts: [CallContext]) -> (() -> Void)? {
        guard lastFromContext === context else {
            return nil
        }

        lastFromContext = nil

        let update = StateUpdate(
            isStateOverridden: stateOverride != nil,
            isOverrideUpdate: false,
            callContexts: callContexts,
            fromContext: context
        )

        let structureDidChange = didStructureUpdate(Models.StateContainer.structureValue(for: state))

        return { [objectWillChange] in
            if !Task.isCancelled {
                context.notify(update)
                if structureDidChange {
                    Task { @MainActor in
                        objectWillChange.send()
                    }
                }
            }
        }
    }

    var context: ChildContext<Models, Models> {
        lock.lock()
        if let context = weakContext {
            lock.unlock()
            return context
        }

        let context = ChildContext<Models, Models>(store: self, path: \.self, parent: nil)
        weakContext = context

        guard !hasBeenActivated else {
            lock.unlock()
            return context
        }

        hasBeenActivated = true
        lock.unlock()

        return context
    }

    func withLocalDependencies<Value>(_ operation: () -> Value) -> Value {
        withDependencies(from: self) {
            operation()
        }
    }
}

extension Store: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: nil)
    }
}

