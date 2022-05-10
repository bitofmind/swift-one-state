import Foundation
import Combine

class Context<State>: ContextBase {
    var observedStates: [AnyKeyPath: (Context<State>, AnyStateChange) -> Bool] = [:]

    typealias Event = (event: Any, path: PartialKeyPath<State>, viewModel: Any)
    var eventSubject = PassthroughSubject<Event, Never>()

    func getCurrent<T>(access: StoreAccess, path: KeyPath<State, T>) -> T { fatalError() }
    func getShared<T>(shared: AnyObject, path: KeyPath<State, T>) -> T { fatalError() }
    func _modify(access: StoreAccess, updateState: (inout State) throws -> Void) rethrows -> AnyStateChange? { fatalError() }
    
    func modify(access: StoreAccess, updateState: (inout State) throws -> Void) rethrows {
        guard let update = try _modify(access: access, updateState: updateState) else { return }
        
        notifyObservedUpdateToAllDescendants(update)
    }
    
    func sendEvent<T>(_ event: Any, path: KeyPath<State, T>, viewModel: Any) {
        eventSubject.send((event: event, path: path, viewModel: viewModel))
    }

    func sendEvent(_ event: Any, viewModel: Any) {
        self.sendEvent(event, path: \.self, viewModel: viewModel)
    }

    override func notifyObservedStateUpdate(_ update: AnyStateChange) {
        let wasUpdated: Bool = lock {
            for equal in observedStates.values {
                guard equal(self, update) else {
#if false
                    let previous = getShared(shared: update.previous, path: \State.self)
                    let current = getShared(shared: update.current, path: \State.self)
                    print("previous", previous)
                    print("current", current)
#endif
                    return true
                }
            }
            return false
        }

        guard wasUpdated else { return }
        
        if Thread.isMainThread {
            observedStateDidUpdate.send()
        } else {
            DispatchQueue.main.async {
                self.observedStateDidUpdate.send()
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
            getCurrent(access: access, path: keyPath)
        }
        set {
            modify(access: access) { state in
                state[keyPath: keyPath] = newValue
            }
        }
    }
    
    subscript<T>(keyPath keyPath: KeyPath<State, T>, access access: StoreAccess) -> T {
        getCurrent(access: access, path: keyPath)
    }
}

extension Context {
    func value<T>(for keyPath: KeyPath<State, T>, access: StoreAccess, isSame: @escaping (T, T) -> Bool) -> T {
        if access == .fromView {
            lock {
                if observedStates.index(forKey: keyPath) == nil {
                    observedStates[keyPath] = { context, update in
                        isSame(
                            context.getShared(shared: update.current, path: keyPath),
                            context.getShared(shared: update.previous, path: keyPath)
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
            return context
        } else {
            let context = ChildContext(context: self, path: path)
            children[path] = context
            return context
        }
    }
}
