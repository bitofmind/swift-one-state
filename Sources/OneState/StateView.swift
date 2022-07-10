public struct StateView<Value> {
    let didUpdate: AsyncStream<Value>
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
    public typealias AsyncIterator = AsyncStream<Value>.AsyncIterator
    public typealias Element = Value

    public func makeAsyncIterator() -> AsyncStream<Value>.AsyncIterator {
        didUpdate.makeAsyncIterator()
    }
}
