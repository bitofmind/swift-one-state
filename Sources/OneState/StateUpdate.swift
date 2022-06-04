import Foundation

public struct StateUpdate<State>: Identifiable {
    var stateChange: AnyStateChange
    var getCurrent: (AnyStateChange) -> State
    var getPrevious: (AnyStateChange) -> State

    public var id: ObjectIdentifier { ObjectIdentifier(stateChange.current) }

    public var previous: State {
        getPrevious(stateChange)
    }

    public var current: State {
        getCurrent(stateChange)
    }
}

public extension StoreViewProvider {
    var stateUpdates: AsyncStream<StateUpdate<State>> {
        let view = self.storeView
        return .init(view.context.stateUpdates.filter { update in
            !update.isOverrideUpdate
        }.map {
            StateUpdate(stateChange: $0, provider: view)
        })
    }
}

extension StateUpdate: Equatable where State: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.current == rhs.current && lhs.previous == rhs.previous
    }
}

extension StateUpdate {
    init<P: StoreViewProvider>(stateChange: AnyStateChange, provider: P) where P.State == State {
        let view = provider.storeView

        self.init(
            stateChange: stateChange,
            getCurrent: { view.context[path: view.path, shared: $0.current] },
            getPrevious: { view.context[path: view.path, shared: $0.previous] }
        )

    }
}
