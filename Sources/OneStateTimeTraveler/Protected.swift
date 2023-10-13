import Foundation

final class Protected<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Value

    init(_ value: Value) {
        _value = value
    }

    var value: Value {
        _read {
            lock.lock()
            yield _value
            lock.unlock()
        }
        _modify {
            lock.lock()
            yield &_value
            lock.unlock()
        }
    }

    func modify<T>(perform: (inout Value) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return perform(&_value)
    }
}
