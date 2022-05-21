import Foundation
import Combine

@dynamicMemberLookup
public struct StateUpdate<Root, State, Access>: Equatable {
    var view: StoreView<Root, State, Access>
    var update: AnyStateChange

    public static func == (lhs: StateUpdate, rhs: StateUpdate) -> Bool {
        lhs.update.current === rhs.update.current
    }

    public var previous: State {
        view.context.getShared(shared: update.previous, path: view.path)
    }

    public var current: State {
        view.context.getShared(shared: update.current, path: view.path)
    }

    public subscript<T: Equatable>(dynamicMember keyPath: KeyPath<State, T>) -> StateUpdate<Root, T, Read> {
        .init(view: StoreView(context: view.context, path: view.path.appending(path: keyPath), access: view.access), update: update)
    }

    public subscript<T: Equatable>(dynamicMember keyPath: KeyPath<State, T?>) -> StateUpdate<Root, T, Read>? {
        view.containerStoreViewElements(for: keyPath).first.map {
            .init(view: $0, update: update)
        }
    }

    public subscript<T: Equatable>(dynamicMember keyPath: KeyPath<State, T>) -> T? {
        let path = view.path.appending(path: keyPath)
        let current = view.context.getShared(shared: update.current, path: path)
        let previous = view.context.getShared(shared: update.previous, path: path)

        return current == previous ? nil : current
    }
}

public extension StoreViewProvider {
    var stateDidUpdatePublisher: AnyPublisher<StateUpdate<Root, State, Access>, Never> {
        let view = self.storeView
        return view.context.stateDidUpdate.filter { update in
            !update.isOverrideUpdate
        }.map {
            StateUpdate(view: view, update: $0)
        }.eraseToAnyPublisher()
    }
}
