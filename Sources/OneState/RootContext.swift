import Foundation
import Combine
import CoreMedia

final class RootContext<State>: Context<State> {
    private var stateLock = Lock()
    
    private var previousState: Shared<State>
    private var currentState: Shared<State>

    private var latestChange: AnyStateChange
    private var currentOverride: StateUpdate<State, State>?
    private var updateTask: Task<(), Never>?

    init(state: State) {
        previousState = Shared(state)
        currentState = previousState
        latestChange = .init(previous: previousState, current: previousState, isOverrideUpdate: false)
        
        super.init(parent: nil)
    }

    override func getCurrent<T>(access: StoreAccess, path: KeyPath<State, T>) -> T {
        stateLock {
            assert(access != .test || isForTesting == true)
            
            if access == .fromView, let current = currentOverride?.update.current {
                return (current as! Shared<State>).value[keyPath: path]
            }
            
            return currentState.value[keyPath: path]
        }
    }
    
    override func getShared<T>(shared: AnyObject, path: KeyPath<State, T>) -> T {
        (shared as! Shared<State>).value[keyPath: path]
    }
    
    override func modify(access: StoreAccess, updateState: (inout State) throws -> Void) rethrows {
        if ContextBase.current != nil {
            fatalError("Not allowed to modify a ViewModel's state from init()")
        }
        
        assert(access != .test || isForTesting == true)
        
        if access == .fromView && isStateOverridden {
            return // Ignore any updates from views while overriding the state
        }

        if isOverrideStore == true {
            // Upgrade to runtime error?
            return assertionFailure("Not allowed to modify state from a overridden store")
        }
        
        try stateLock {
            if previousState === currentState {
                currentState = .init(previousState.value)
            }
            try updateState(&currentState.value)
        }
        
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            update()
        }
    }
    
    override var isStateOverridden: Bool {
        stateOverride != nil
    }
}

extension RootContext {
    var latestUpdate: StateUpdate<State, State> {
        let view = StoreView(context: self, path: \.self, access: .fromView)
        return .init(view: view, update: stateLock { latestChange })
    }

    var stateOverride: StateUpdate<State, State>? {
        get {
            stateLock { currentOverride }
        }
        set {
            let update: AnyStateChange? = stateLock {
                let current = currentOverride?.update.current
                let previous = (currentOverride?.update.current ?? currentState)
                currentOverride = newValue

                guard let current = newValue?.update.current ?? current,
                      previous !== current else { return nil }

                return .init(previous: previous, current: current, isOverrideUpdate: true)
            }

            guard let update = update else { return }

            notifyStateUpdate(update)
            stateDidUpdate.send(update)
        }
    }
}

private extension RootContext {
    func update() {
        let update: AnyStateChange? = stateLock {
            let state = currentState
            guard previousState !== state else { return nil }

            defer { previousState = state }
            return .init(previous: previousState, current: state, isOverrideUpdate: false)
        }
        
        guard let update = update else { return }
        
        notifyStateUpdate(update)
        stateDidUpdate.send(update)
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
    var isOverrideUpdate: Bool
}
