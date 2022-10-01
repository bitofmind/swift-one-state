import Foundation
import CustomDump

@propertyWrapper
@dynamicMemberLookup
public struct Writable<Value> {
    public var wrappedValue: Value
    
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    public var projectedValue: Writable {
        get { self }
        set { self = newValue }
    }

    subscript<T>(dynamicMember path: WritableKeyPath<Value, T>) -> Writable<T> {
        get { .init(wrappedValue:  wrappedValue[keyPath: path]) }
        set { wrappedValue[keyPath: path] = newValue.wrappedValue }
    }
}

extension Writable: Sendable where Value: Sendable {}

extension Writable: Equatable where Value: Equatable {}

extension Writable: Decodable where Value: Decodable {
    public init(from decoder: Decoder) throws {
        wrappedValue = try .init(from: decoder)
    }
}

extension Writable: Encodable where Value: Encodable {
    public func encode(to encoder: Encoder) throws {
        try wrappedValue.encode(to: encoder)
    }
}

extension Writable: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

extension Writable: CustomDumpRepresentable {
    public var customDumpValue: Any {
        wrappedValue
    }
}


