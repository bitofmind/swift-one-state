import Foundation
import Combine

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
    
    public var valueDidChangePublisher: AnyPublisher<Value, Never> {
        subject.eraseToAnyPublisher()
    }
}
