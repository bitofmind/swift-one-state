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
    
    private let lock = NSRecursiveLock()

    private var previousState: Shared<State>
    private var currentState: Shared<State>
    private var modifyCount = 0

    private var currentOverride: StateUpdate<State>?

    private var updateTask: Task<(), Never>?
    private var updateTaskPriority: TaskPriority = .medium
    private var lastFromContext: ContextBase?
    private var lastCallContexts: [CallContext] = []

    private(set) weak var weakContext: ChildContext<M, M>?
    private var dependencies: [ObjectIdentifier: Any] = [:]
    private var hasBeenActivated = false

    let cancellations = Cancellations()

    public init(initialState: State) {
        previousState = Shared(initialState)
        currentState = previousState
    }
}

public extension Store {
    var model: M {
        M(self)
    }

    func dependency<Value>(_ path: WritableKeyPath<ModelDependencyValues, Value>, _ value: Value) -> Self {
        updateDependency(path, value)
        return self
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

            weakContext?.notify(update)
        }
    }
}

extension Store {
    var sharedState: Shared<State> {
        lock {
            currentState
        }
    }

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
            lock.lock()
            yield currentState.value[keyPath: path]
            lock.unlock()
        }
        _modify {
            let isOverrideContext = fromContext.isOverrideContext
            lock.lock()

            if currentOverride != nil, isOverrideContext {
                // Upgrade to runtime error?
                assertionFailure("Not allowed to modify state from a overridden store")
                yield &currentState.value[keyPath: path]
                lock.unlock()
                return
            }

            let callContexts = CallContext.currentContexts

            var flushNotify: (() -> Void)?
            if let last = lastFromContext, (last !== fromContext || lastCallContexts != callContexts || Task.currentPriority > updateTaskPriority) {
                updateTask?.cancel()
                flushNotify = notifier(context: last, callContexts: lastCallContexts)
                updateTask = nil
            }

            if previousState === currentState {
                currentState = .init(previousState.value)
            }

            yield &currentState.value[keyPath: path]
            lastFromContext = fromContext
            lastCallContexts = callContexts
            modifyCount += 1

            if updateTask == nil {
                // Try to coalesce updates
                updateTaskPriority = Task.currentPriority
                updateTask = Task {
                    while true {
                        let count = self.lock { self.modifyCount }
                        try? await Task.sleep(nanoseconds: NSEC_PER_MSEC*10)

                        let shouldBreak = self.lock {
                            guard count == self.modifyCount else { return false }
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

    func notifier(context: ContextBase, callContexts: [CallContext]) -> (() -> Void)? {
        let state = currentState
        guard previousState !== state, lastFromContext === context else {
            return nil
        }

        lastFromContext = nil

        let update = AnyStateChange(
            previous: previousState,
            current: state,
            isStateOverridden: currentOverride != nil,
            isOverrideUpdate: false,
            callContexts: callContexts
        )

        previousState = state

        return {
            if !Task.isCancelled {
                context.notify(update)
            }
        }
    }

    var isUpdateInProgress: Bool {
        lock { previousState !== currentState }
    }

    var context: ChildContext<M, M> {
        lock.lock()
        if let context = weakContext {
            lock.unlock()
            return context
        }

        let context = ChildContext<M, M>(store: self, path: \.self, parent: nil)
        for (key, value) in dependencies {
            context.dependencies[key] = value
        }

        weakContext = context

        guard !hasBeenActivated else {
            lock.unlock()
            return context
        }

        hasBeenActivated = true
        lock.unlock()
        ContextBase.$current.withValue(nil) {
            context.model.onActivate()
        }
        return context
     }

    func updateDependency<Value>(_ path: WritableKeyPath<ModelDependencyValues, Value>, _ value: Value) {
        var d = ModelDependencyValues { _ in
            nil
        } set: { key, value in
            self.lock {
                self.dependencies[key] = value
            }
            self.weakContext?.dependencies[key] = value
        }
        d[keyPath: path] = value
    }
}

extension Store: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: nil)
    }
}

