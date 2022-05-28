import Foundation

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
}

public extension StoreViewProvider {
    var stateUpdates: AsyncStream<StateUpdate<Root, State, Access>> {
        let view = self.storeView
        return .init(view.context.stateUpdates.filter { update in
            !update.isOverrideUpdate
        }.map {
            StateUpdate(view: view, update: $0)
        })
    }
}
