import Foundation
import Combine
#if canImport(CustomDump)
import CustomDump
#endif

class Context<State>: ContextBase {
    var observedStates: [AnyKeyPath: (Context<State>, AnyStateChange) -> Bool] = [:]

    // TODO: rename
    func getCurrent(access: StoreAccess, path: PartialKeyPath<State>) -> Any { fatalError() }
    func getShared(shared: AnyObject, path:  PartialKeyPath<State>) -> Any { fatalError() }
    func modify(access: StoreAccess, updateState: (inout State) throws -> Void) rethrows { fatalError() }
    
    override func notifyStateUpdate(_ update: AnyStateChange) {
        guard (update.isOverrideUpdate && isStateOverridden) || (!update.isOverrideUpdate && !isStateOverridden)  else {
            return
        }
        
        let wasUpdated: Bool = lock {
            for equal in observedStates.values {
                guard equal(self, update) else {
#if false //canImport(CustomDump)
                    let previous = getShared(shared: update.previous, path: \State.self) as! State
                    let current = getShared(shared: update.current, path: \State.self) as! State
                    if let d = diff(previous, current) {
                        print(d)
                    } else {
                        print("previous", previous)
                        print("current", current)
                    }
#endif

                    return true
                }
            }
            return false
        }

        if wasUpdated {
            if Thread.isMainThread {
                observedStateDidUpdate.send()
            } else {
                DispatchQueue.main.async {
                    self.observedStateDidUpdate.send()
                }
            }
        }
    }
    
    override var isStateOverridden: Bool {
        parent?.isStateOverridden ?? false
    }
}

enum StoreAccess {
    case fromView
    case fromViewModel
    case test
}

extension Context {
    subscript<T>(keyPath keyPath: WritableKeyPath<State, T>, access access: StoreAccess) -> T {
        get {
            getCurrent(access: access, path: keyPath) as! T
        }
        set {
            modify(access: access) { state in
                state[keyPath: keyPath] = newValue
            }
        }
    }
    
    subscript<T>(keyPath keyPath: KeyPath<State, T>, access access: StoreAccess) -> T {
        self.getCurrent(access: access, path: keyPath) as! T
    }
}

extension Context {
    func value<T>(for keyPath: KeyPath<State, T>, access: StoreAccess, isSame: @escaping (T, T) -> Bool) -> T {
        if access == .fromView {
            lock {
                if observedStates.index(forKey: keyPath) == nil {
                    observedStates[keyPath] = { context, update in
                        isSame(
                            context.getShared(shared: update.current, path: keyPath) as! T,
                            context.getShared(shared: update.previous, path: keyPath) as! T
                        )
                    }
                }
            }
        }
        
        return self[keyPath: keyPath, access: access]
    }
    
    func value<T: Equatable>(for keyPath: KeyPath<State, T>, access: StoreAccess) -> T {
        value(for: keyPath, access: access, isSame: ==)
    }

    func value<T>(for keyPath: KeyPath<State, T>, access: StoreAccess) -> T {
        value(for: keyPath, access: access, isSame: { _, _ in false })
    }
}

extension Context {
    func context<T>(at path: WritableKeyPath<State, T>) -> Context<T> {
        if let _store = children[path] {
            return _store as! Context<T>
        } else if parent == nil && path == (\State.self as AnyKeyPath) {
            let context = self as! Context<T>
            children[path] = context
            context.isFullyInitialized = context.isForTesting
            return context
        } else {
            let context = ChildContext(context: self, path: path)
            children[path] = context
            context.isFullyInitialized = context.isForTesting
            return context
        }
    }
}
