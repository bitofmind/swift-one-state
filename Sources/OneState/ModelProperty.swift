import Foundation
import AsyncAlgorithms

/// Declares a value stored outside of a model's store
///
/// This is useful for state that is derived or cached from the models state,
/// where we don't want the value to refelected in the state it self
///
///     @ModelProperty var cancellable: AnyCancellable? = nil
@propertyWrapper
public struct ModelProperty<Value> {
    let context: ContextBase
    let index: Int

    public init(wrappedValue: @escaping @autoclosure () -> Value) {
        guard let ctx = ContextBase.current else {
            fatalError("Not allowed to access a ViewModel's property when not presented from a view")
        }

        context = ctx
        index = context.propertyIndex
        context.propertyIndex += 1

        if index == context.properties.count {
            context.properties.append(Box(wrappedValue()))
        }
    }

    public var wrappedValue: Value {
        get {
            box.value
        }
        nonmutating set {
            box.value = newValue
            box.subject.yield(newValue)
        }
    }

    public var projectedValue: Self {
        return self
    }
}

extension ModelProperty: AsyncSequence {
    public typealias AsyncIterator = AsyncStream<Value>.AsyncIterator
    public typealias Element = Value

    public func makeAsyncIterator() -> AsyncStream<Value>.AsyncIterator {
        AsyncStream(chain([wrappedValue].async, box.subject)).makeAsyncIterator()
    }
}

public extension ModelProperty where Value: Equatable {
    var stateView: StateView<Value> {
        .init(didUpdate: .init(self)) {
            wrappedValue
        } set: {
            wrappedValue = $0
        }
    }
}

extension ModelProperty {
    class Box {
        let subject = AsyncPassthroughSubject<Value>()
        var value: Value

        init(_ value: Value) {
            self.value = value
        }
    }

    var box: Box {
        context.properties[index] as! Box
    }
}

