import Foundation

extension NSLocking {
    func callAsFunction<T>(_ operation: () throws -> T) rethrows -> T {
        try withLock(operation)
    }
}

struct Lock {
    private var _lock = os_unfair_lock_s()
    
    mutating func lock() {
        os_unfair_lock_lock(&_lock)
    }

    mutating func unlock() {
        os_unfair_lock_unlock(&_lock)
    }
    
    mutating func callAsFunction<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

protocol HoldsLock: AnyObject {
    var lock: Lock { get set }
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
}

final class Protected<Value: Sendable>: @unchecked Sendable {
    private var lock = Lock()
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
