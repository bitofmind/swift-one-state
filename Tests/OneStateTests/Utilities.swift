import XCTest
@testable import OneState

@Sendable func assertNoFailure<State>(failure: TestFailure<State>) {
    XCTFail(failure.message, file: failure.file, line: failure.line)
}

final class Locked<Value> {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        get { lock { _value } }
        set { lock { _value = newValue } }
    }

    func callAsFunction<T>(_ operation: (inout Value) -> T) -> T {
        lock {
            operation(&_value)
        }
    }
}

extension Locked: @unchecked Sendable where Value: Sendable {}

extension NSLock {
    func callAsFunction<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}
