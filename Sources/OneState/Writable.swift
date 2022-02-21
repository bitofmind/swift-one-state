import Foundation

@propertyWrapper
public struct Writable<Value> {
    public var wrappedValue: Value
    
    public init(wrappedValue: Value) {
        self.wrappedValue = wrappedValue
    }
    
    public var projectedValue: Writable {
        get { self }
        set { self = newValue }
    }
}

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

