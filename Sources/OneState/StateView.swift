
@dynamicMemberLookup
public struct StateView<Value> {
    let didUpdate: AsyncStream<Value>
    let get: () -> Value
    let set: (Value) ->()
}

public extension StateView {
    var value: Value {
        get { get() }
        nonmutating set { set(newValue) }
    }

    subscript<T>(dynamicMember path: WritableKeyPath<Value, T>) -> StateView<T> {
        .init(didUpdate: .init(didUpdate.map { $0[keyPath: path] } )) {
            value[keyPath: path]
        } set:  {
            value[keyPath: path]  = $0
        }
    }
}

extension StateView: AsyncSequence where Value: Equatable {
    public typealias AsyncIterator = AsyncStream<Value>.AsyncIterator
    public typealias Element = Value

    public func makeAsyncIterator() -> AsyncStream<Value>.AsyncIterator {
        didUpdate.makeAsyncIterator()
    }
}
