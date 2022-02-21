import Foundation

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
        get {
            instance.lock {
                instance[keyPath: storageKeyPath]._wrappedValue
            }
        }
        set {
            instance.lock {
                instance[keyPath: storageKeyPath]._wrappedValue = newValue
            }
        }
    }
    
    @available(*, unavailable,  message: "This property wrapper can only be applied to reference holding a Lock" )
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}
