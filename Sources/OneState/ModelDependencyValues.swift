import Foundation

public protocol ModelDependencyKey {
    associatedtype Value: Sendable
    static var defaultValue: Value { get }
}

public struct ModelDependencyValues: Sendable {
    var get: @Sendable (ObjectIdentifier) -> Any?
    var set: @Sendable (ObjectIdentifier, Any?) -> ()

    public subscript<Key: ModelDependencyKey>(key: Key.Type) -> Key.Value {
        get {
            get(ObjectIdentifier(key)) as? Key.Value ?? Key.defaultValue
        }
        nonmutating set {
            set(ObjectIdentifier(key), newValue)
        }
    }
}

public extension ModelDependencyValues {
    var date: @Sendable () -> Date {
        get { self[DateKey.self] }
        set { self[DateKey.self] = newValue }
    }

    var uuid: @Sendable () -> UUID {
        get { self[UUIDKey.self] }
        set { self[UUIDKey.self] = newValue }
    }
}

private enum DateKey: ModelDependencyKey {
    static let defaultValue = { @Sendable in Date() }
}

private enum UUIDKey: ModelDependencyKey {
    static let defaultValue = { @Sendable in UUID() }
}
