import Foundation

extension NSLocking {
    func callAsFunction<T>(_ operation: () throws -> T) rethrows -> T {
        try withLock(operation)
    }
}

protocol HoldsLock: AnyObject {
    associatedtype Lock: NSLocking
    var lock: Lock { get }
}

@propertyWrapper
struct Locked<Value> {
    private var _wrappedValue: Value
    
    init(wrappedValue: Value) {
        _wrappedValue = wrappedValue
    }
    
    static subscript<T: HoldsLock>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value {
        _read {
            instance.lock.lock()
            defer { instance.lock.unlock() }
            yield instance[keyPath: storageKeyPath]._wrappedValue
        }
        _modify {
            instance.lock.lock()
            defer { instance.lock.unlock() }
            yield &instance[keyPath: storageKeyPath]._wrappedValue
        }
    }
    
    @available(*, unavailable,  message: "This property wrapper can only be applied to reference holding a Lock" )
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }

    var projectedValue: Value {
        get { _wrappedValue }
        set { _wrappedValue = newValue }
    }
}

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
