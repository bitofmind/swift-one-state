import Foundation
import Combine

@dynamicMemberLookup
public struct StateUpdate<Root, State>: Equatable {
    var view: StoreView<Root, State>
    var update: AnyStateChange

    public static func == (lhs: StateUpdate, rhs: StateUpdate) -> Bool {
        lhs.update.current === rhs.update.current
    }

    public var previous: State {
        view.context.getShared(shared: update.previous, path: view.path) as! State
    }
    
    public var current: State {
        view.context.getShared(shared: update.current, path: view.path) as! State
    }

    public subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, T>) -> StateUpdate<Root, T> {
        .init(view: StoreView(context: view.context, path: view.path.appending(path: keyPath), access: view.access), update: update)
    }

    public subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, T?>) -> StateUpdate<Root, T>? {
        let optionPath = view.path(keyPath)
        guard let initial = view.context[keyPath: optionPath, access: view.access] else {
            return nil
        }
        
        let unwrapPath = optionPath.appending(path: \T?[unwrapFallback: .init(initial)])
        return .init(view: StoreView(context: view.context, path: unwrapPath, access: view.access), update: update)
    }

    public subscript<T: Equatable>(dynamicMember keyPath: KeyPath<State, T>) -> T? {
        let path = view.path.appending(path: keyPath)
        let current = view.context.getShared(shared: update.current, path: path) as! T
        let previous = view.context.getShared(shared: update.previous, path: path) as! T

        return current == previous ? nil : current
    }
}

public extension StoreViewProvider {
    var stateDidUpdatePublisher: AnyPublisher<StateUpdate<Root, State>, Never> {
        var view = self.storeView
        view.access = StoreAccess.viewModel ?? view.access
        return view.context.stateDidUpdate.filter { update in
            switch (view.context.isStateOverridden, update.isOverrideUpdate, view.access) {
            case (false, false, _): return true
            case (true, false, .fromViewModel): return true
            case (true, true, .fromView): return true
            default: return false
            }
        }.map {
            StateUpdate(view: view, update: $0)
        }.eraseToAnyPublisher()
    }
}
