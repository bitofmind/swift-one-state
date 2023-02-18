public struct StateView<Value> {
    let didUpdate: AnyAsyncSequence<Value>
    let get: @Sendable () -> Value
    let set: @Sendable (Value) ->()

    public var wrappedValue: Value {
        get { get() }
        set { set(newValue) }
    }
}

extension StateView: Sendable where Value: Sendable {}

public extension StateView {
    var value: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }
}

extension StateView: AsyncSequence {
    public typealias Element = Value

    public func makeAsyncIterator() -> AnyAsyncIterator<Value> {
        didUpdate.makeAsyncIterator()
    }
}

public extension ModelState {
    func view<Value: Sendable&Equatable>(for path: WritableKeyPath<State, Value>) -> StateView<Value> {
        let view = self[dynamicMember: path]
        return .init(didUpdate: .init(view.values)) {
            view.nonObservableState
        } set: {
            view.context[path: view.path] = $0
        }
    }
}

public extension ModelState where State: Sendable&Equatable {
    var view: StateView<State> {
        return view(for: \.self)
    }
}

