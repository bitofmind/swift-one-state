import Foundation
import Combine

class Context<State>: ContextBase {
    typealias Event = (event: Any, path: PartialKeyPath<State>, viewModel: Any)
    var eventSubject = PassthroughSubject<Event, Never>()

    func getCurrent<T>(atPath path: KeyPath<State, T>, access: StoreAccess?) -> T { fatalError() }
    func getShared<T>(shared: AnyObject, path: KeyPath<State, T>) -> T { fatalError() }
    func _modify(fromContext: ContextBase, access: StoreAccess?, updateState: (inout State) throws -> Void) rethrows { fatalError() }
    
    func modify(access: StoreAccess?, updateState: (inout State) throws -> Void) rethrows {
        try _modify(fromContext: self, access: access, updateState: updateState)
    }
    
    func sendEvent<T>(_ event: Any, path: KeyPath<State, T>, viewModel: Any) {
        eventSubject.send((event: event, path: path, viewModel: viewModel))
    }

    func sendEvent(_ event: Any, viewModel: Any) {
        self.sendEvent(event, path: \.self, viewModel: viewModel)
    }
    
    override var isStateOverridden: Bool {
        parent?.isStateOverridden ?? false
    }
}

class StoreAccess {
    func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) { fatalError() }

    var allowAccessToBeOverridden: Bool { fatalError() }

    @TaskLocal static var current: StoreAccess?
    @TaskLocal static var isInViewModelContext = false
}

extension Context {
    subscript<T>(path path: WritableKeyPath<State, T>, access access: StoreAccess?) -> T {
        get {
            getCurrent(atPath: path, access: access)
        }
        set {
            modify(access: access) { state in
                state[keyPath: path] = newValue
            }
        }
    }
    
    subscript<T>(path path: KeyPath<State, T>, access access: StoreAccess?) -> T {
        getCurrent(atPath: path, access: access)
    }
}

extension Context {
    func value<T>(for path: KeyPath<State, T>, access: StoreAccess?, isSame: @escaping (T, T) -> Bool) -> T {
        if !StoreAccess.isInViewModelContext {
            access?.willAccess(path: path, context: self, isSame: isSame)
        }
        return self[path: path, access: access]
    }
    
    func value<T: Equatable>(for path: KeyPath<State, T>, access: StoreAccess?) -> T {
        value(for: path, access: access, isSame: ==)
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
