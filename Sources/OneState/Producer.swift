import Foundation

public struct ProducerOf<Value>: Sendable {
    let produce: @Sendable () -> Value

    public init(produce: @escaping @Sendable () -> Value) {
        self.produce = produce
    }

    public func callAsFunction() -> Value {
        produce()
    }
}

public extension ProducerOf where Value: Sendable {
    static func constant(_ value: Value) -> Self {
        Self { @Sendable in value }
    }
}

#if swift(<5.7)
extension UUID: @unchecked Sendable {}
extension Date: @unchecked Sendable {}
#endif

public extension ProducerOf where Value == UUID {
    static let live = Self { UUID() }
}

public extension ProducerOf where Value == Date {
    static let live = Self { Date() }
}


