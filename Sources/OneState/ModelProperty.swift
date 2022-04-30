import Foundation
import Combine

/// Declares a value stored outside of a models store
///
/// This is useful for state that is derived or cached from the models state,
/// where we don't want the value to refelected in the state it self
///
///     @ModelProperty var cancellable: AnyCancellable? = nil
@propertyWrapper
public struct ModelProperty<Value> {
    let context: ContextBase
    let index: Int
    typealias Subject = CurrentValueSubject<Value, Never>
    
    public init(wrappedValue: @escaping @autoclosure () -> Value) {
        guard let ctx = ContextBase.current else {
            fatalError("Not allowed to access a ViewModel's property when not presented from a view")
        }
        
        context = ctx
        index = context.propertyIndex
        context.propertyIndex += 1
        
        if index == context.properties.count {
            context.properties.append(Subject(wrappedValue()))
        }
    }
    
    var subject: Subject {
        context.properties[index] as! Subject
    }
    
    public var wrappedValue: Value {
        get {
            subject.value
        }
        nonmutating set {
            subject.value = newValue
        }
    }
    
    public var projectedValue: Self {
        return self
    }
}

extension ModelProperty: Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    
    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == Value, S.Failure == Never {
        subject.receive(subscriber: subscriber)
    }
}
