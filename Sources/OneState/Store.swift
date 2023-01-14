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

    private var overrideState: State?

    private var updateTask: Task<(), Never>?
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

    var state: State {
        _read {
            lock.lock()
            yield currentState.value
            lock.unlock()
        }
    }

    func dependency<Value>(_ path: WritableKeyPath<ModelDependencyValues, Value>, _ value: Value) -> Self {
        updateDependency(path, value)
        return self
    }

    /// Used to override state when replaying recorded state
    var stateOverride: State? {
        get { lock { overrideState } }
        set {
            lock { overrideState = newValue }
            weakContext?.notify(StateChange(isStateOverridden: true, isOverrideUpdate: true))
        }
    }

}

extension Store {
    subscript<T> (path path: KeyPath<State, T>) -> T {
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

            if stateOverride != nil, isOverrideContext {
                // Upgrade to runtime error?
                assertionFailure("Not allowed to modify state from a overridden store")
                yield &currentState.value[keyPath: path]
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

            if previousState === currentState {
                currentState = .init(previousState.value)
            }

            yield &currentState.value[keyPath: path]
            lastFromContext = fromContext
            lastCallContexts = callContexts
            modifyCount += 1

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
        let state = currentState
        guard previousState !== state, lastFromContext === context else {
            return nil
        }

        lastFromContext = nil

        let update = StateChange(
            isStateOverridden: stateOverride != nil,
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

