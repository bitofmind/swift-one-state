import Foundation

final class RootContext<State>: Context<State> {
    private var stateLock = Lock()
    
    private var previousState: Shared<State>
    private var currentState: Shared<State>

    private var currentOverride: StateUpdate<State, State, Write>?
    private var updateTask: Task<(), Never>?
    private var lastFromContext: ContextBase?

    init(state: State) {
        previousState = Shared(state)
        currentState = previousState
        super.init(parent: nil)
    }

    override func getCurrent<T>(atPath path: KeyPath<State, T>, access: StoreAccess?) -> T {
        stateLock {
            if access?.allowAccessToBeOverridden == true, let current = currentOverride?.update.current {
                return (current as! Shared<State>).value[keyPath: path]
            }
            
            return currentState.value[keyPath: path]
        }
    }
    
    override func getShared<T>(shared: AnyObject, path: KeyPath<State, T>) -> T {
        (shared as! Shared<State>).value[keyPath: path]
    }
    
    override func _modify(fromContext: ContextBase, access: StoreAccess?, updateState: (inout State) throws -> Void) rethrows {
        if ContextBase.current != nil {
            fatalError("Not allowed to modify a ViewModel's state from init()")
        }

        if access?.allowAccessToBeOverridden == true && isStateOverridden {
            return // Ignore any updates from views while overriding the state
        }

        if isOverrideStore == true {
            // Upgrade to runtime error?
            assertionFailure("Not allowed to modify state from a overridden store")
            return
        }

        let lastContext: ContextBase? = stateLock { lastFromContext }

        if let last = lastContext, last !== fromContext, CallContext.current != nil {
            notify(context: last)
        }

        try stateLock {
            if previousState === currentState {
                currentState = .init(previousState.value)
            }
            try updateState(&currentState.value)
            lastFromContext = fromContext
        }

        updateTask?.cancel()

        if let callContext = CallContext.current {
            callContext {
                notify(context: fromContext)
            }
        } else {
            updateTask = Task { @MainActor in
                guard !Task.isCancelled else { return }
                notify(context: fromContext)
            }
        }
    }

    override var isStateOverridden: Bool {
        stateOverride != nil
    }

    func notify(context: ContextBase) {
        let update: AnyStateChange? = stateLock {
            let state = currentState
            guard previousState !== state, lastFromContext === context else { return nil }
            lastFromContext = nil

            defer { previousState = state }
            return .init(previous: previousState, current: state, isStateOverridden: currentOverride != nil, isOverrideUpdate: false, callContext: .current)
        }

        guard let update = update else { return }

        context.notifyAncestors(update)
        context.stateUpdates.yield(update)
        context.notifyDescendants(update)
    }
}

extension RootContext {
    var latestUpdate: StateUpdate<State, State, Write> {
        let view = StoreView(context: self, path: \.self, access: nil)
        return .init(view: view, update: stateLock {
            .init(previous: previousState, current: previousState, isStateOverridden: currentOverride != nil, isOverrideUpdate: false)
        })
    }

    var stateOverride: StateUpdate<State, State, Write>? {
        get {
            stateLock { currentOverride }
        }
        set {
            let update: AnyStateChange? = stateLock {
                let previous = currentOverride?.update.current ?? currentState
                let current = newValue?.update.current ?? currentState
                currentOverride = newValue

                guard previous !== current else { return nil }

                return .init(previous: previous, current: current, isStateOverridden: true, isOverrideUpdate: true)
            }

            guard let update = update else { return }

            stateUpdates.yield(update)
            notifyDescendants(update)
        }
    }
}

final class Shared<Value> {
    var value: Value
    
    init(_ value: Value) {
        self.value = value
    }
}

struct AnyStateChange {
    var previous: AnyObject
    var current: AnyObject
    var isStateOverridden: Bool
    var isOverrideUpdate: Bool
    var callContext: CallContext?
}
