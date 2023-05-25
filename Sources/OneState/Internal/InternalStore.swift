import Foundation
import Dependencies

final class InternalStore<Models: ModelContainer>: ObservableObject, @unchecked Sendable {
    typealias State = Models.Container

    @Dependency(\.uuid) private var dependencies
    private let lock = NSRecursiveLock()

    private var currentState: State
    private var modifyCount = 0
    private var overrideState: State?
    private var overrideSinkState: State

    private var updateTask: Task<(), Never>?
    private var lastFromContext: ContextBase?
    private var lastCallContexts: [CallContext] = []

    let cancellations = Cancellations()
    private var didStructureUpdate: (Models.StateContainer.StructureValue) -> Bool = { _ in false }

    init(initialState: State, dependencies: @escaping (inout DependencyValues) -> Void = { _ in }) {
        currentState = initialState
        overrideSinkState = initialState
        withDependencies(from: self) {
            dependencies(&$0)
        } operation: {
            _dependencies = Dependency(\.uuid)
        }
    }
}

extension InternalStore {
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
        set { lock { overrideState = newValue } }
    }
}

extension InternalStore where Models.StateContainer: DefaultedStateContainer {
    convenience init(delayedInitialState: @escaping (inout DependencyValues) async -> (ChildContext<Models, Models>, State)) {
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
                let (context, state) = await delayedInitialState(&$0)
                self[path: \.self, fromContext: context] = state
            } operation: {
                _dependencies = Dependency(\.uuid)
            }
        }
    }

    func delayedInitialState(contextAndState: @escaping (inout DependencyValues) async -> (ChildContext<Models, Models>, State)) async {
        var lastStructure = Models.StateContainer.structureValue(for: state)
        self.didStructureUpdate = { newStructure in
            if newStructure != lastStructure {
                lastStructure = newStructure
                return true
            }
            return false

        }
        await withDependencies(from: self) {
            let (context, state) = await contextAndState(&$0)
            self[path: \.self, fromContext: context] = state
        } operation: {
            _dependencies = Dependency(\.uuid)
        }
    }
}

extension InternalStore {
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
            context.notify(update)
            if structureDidChange {
                Task { @MainActor in
                    objectWillChange.send()
                }
            }
        }
    }

    func withLocalDependencies<Value>(_ operation: () -> Value) -> Value {
        withDependencies(from: self) {
            operation()
        }
    }
}
