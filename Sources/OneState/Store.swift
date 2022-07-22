import Foundation

/// A store holds the state of an application or part of a applicaton
///
/// From its state or a sub-state of that state, models are insantiated to maintain
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
public final class Store<M: Model>: @unchecked Sendable {
    public typealias State = M.State
    
    private var lock = Lock()

    private var previousState: Shared<State>
    private var currentState: Shared<State>
    private var modifyCount = 0

    private var currentOverride: StateUpdate<State>?

    private var updateTask: Task<(), Never>?
    private var lastFromContext: ContextBase?
    private var lastCallContextIds: [CallContext.ID] = []

    private(set) var context: ChildContext<M, State>!

    private var _activeTasks: [ObjectIdentifier: (description: () -> String, count: Int)] = [:]

    let fallbackStore: Store!

    public init(initialState: State, environments: [Any] = []) {
        previousState = Shared(initialState)
        currentState = previousState
        context = nil
        fallbackStore = Self(fallbackState: initialState)

        context = .init(store: self, path: \.self, parent: nil)
        for environment in environments {
            context.environments[ObjectIdentifier(type(of: environment))] = environment
        }
    }

    private init(fallbackState: State) {
        previousState = Shared(fallbackState)
        currentState = previousState
        context = nil
        fallbackStore = nil
    }
}

public extension Store {
    convenience init<T>(initialState: T, environments: [Any] = []) where M == EmptyModel<T> {
        self.init(initialState: initialState, environments: environments)
    }

    var model: M {
        M(self)
    }

    func updateEnvironment<Value>(_ value: Value) {
        context.environments[ObjectIdentifier(Value.self)] = value
    }

    /// Access the the lastest update useful for debugging or initial state for state recording
    var latestUpdate: StateUpdate<State> {
        .init(
            stateChange: lock {
                .init(previous: previousState, current: previousState, isStateOverridden: currentOverride != nil, isOverrideUpdate: false)
            },
            getCurrent: { ($0.current as! Shared<State>).value },
            getPrevious: { ($0.previous as! Shared<State>).value }
        )
    }

    /// Used to override state when replaying recorded state
    var stateOverride: StateUpdate<State>? {
        get {
            lock { currentOverride }
        }
        set {
            lock.lock()

            let previous = currentOverride?.stateChange.current ?? currentState
            let current = newValue?.stateChange.current ?? currentState
            currentOverride = newValue

            guard previous !== current else { return lock.unlock() }

            let update = AnyStateChange(previous: previous, current: current, isStateOverridden: true, isOverrideUpdate: true)
            lock.unlock()

            context.notify(update)
        }
    }
}

extension Store {
    var state: State {
        _read {
            lock.lock()
            yield currentState.value
            lock.unlock()
        }
    }

    subscript<T> (path path: KeyPath<State, T>, fromContext fromContext: ContextBase) -> T {
        _read {
            lock.lock()
            yield currentState.value[keyPath: path]
            lock.unlock()
        }
    }

    subscript<T> (path path: WritableKeyPath<State, T>, fromContext fromContext: ContextBase) -> T {
        _read {
            yield currentState.value[keyPath: path]
        }
        _modify {
            lock.lock()

            if currentOverride != nil, fromContext.isOverrideStore {
                // Upgrade to runtime error?
                assertionFailure("Not allowed to modify state from a overridden store")
                yield &currentState.value[keyPath: path]
                lock.unlock()
                return
            }

            let currentCallContextIds = CallContext.currentContexts.map(\.id)
            if let last = lastFromContext, (last !== fromContext || lastCallContextIds != currentCallContextIds) {
                lock.unlock()
                updateTask?.cancel()
                updateTask = nil
                notify(context: last)
                lock.lock()
            }

            if previousState === currentState {
                currentState = .init(previousState.value)
            }

            yield &currentState.value[keyPath: path]
            lastFromContext = fromContext
            lastCallContextIds = currentCallContextIds
            modifyCount += 1

            if updateTask == nil {
                // Try to coalesce updates
                updateTask = Task { @MainActor in
                    while true {
                        let count = self.lock { self.modifyCount }

                        await Task.yield()

                        self.lock.lock()
                        defer { self.lock.unlock() }
                        
                        if count == self.modifyCount {
                            self.updateTask = nil
                            break
                        }
                    }

                    if !Task.isCancelled {
                        self.notify(context: fromContext)
                    }
                }
            }
            
            lock.unlock()
        }
    }

    subscript<T> (path path: KeyPath<State, T>, shared shared: AnyObject) -> T {
        _read {
            let shared = shared as! Shared<State>
            yield shared.value[keyPath: path]
        }
    }

    subscript<T> (path path: WritableKeyPath<State, T>, shared shared: AnyObject) -> T {
        _read {
            let shared = shared as! Shared<State>
            yield shared.value[keyPath: path]
        }
        _modify {
            let shared = shared as! Shared<State>
            yield &shared.value[keyPath: path]
        }
    }

    subscript<T> (overridePath path: KeyPath<State, T>) -> T? {
        _read {
            lock.lock()
            if let override = currentOverride?.current {
                yield override[keyPath: path]
            } else {
                yield nil
            }
            lock.unlock()
        }
    }

    func notify(context: ContextBase) {
        lock.lock()

        let state = currentState
        guard previousState !== state, lastFromContext === context else {
            lock.unlock()
            return
        }

        lastFromContext = nil

        let update = AnyStateChange(
            previous: previousState,
            current: state,
            isStateOverridden: currentOverride != nil,
            isOverrideUpdate: false,
            callContexts: CallContext.currentContexts
        )

        previousState = state
        lock.unlock()

        context.notify(update)
    }

    var isUpdateInProgress: Bool {
        lock { previousState !== currentState }
    }

    func pushTask<M: Model>(for model: M, isInActivationContext: Bool) {
        lock {
            guard !isInActivationContext else { return }
            _activeTasks[ObjectIdentifier(type(of: model)), default: ({ model.typeDescription }, 0)].count += 1
        }
    }

    func popTask<M: Model>(for model: M, isInActivationContext: Bool) {
        lock {
            guard !isInActivationContext else { return }
            _activeTasks[ObjectIdentifier(type(of: model))]!.count -= 1
        }
    }

    var activeTasks: [(modelName: String, count: Int)] {
        lock {
            _activeTasks.values.filter { $0.count != 0 }.map { ($0.description(), $0.count) }
        }
    }
}

extension Store: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: nil)
    }
}
