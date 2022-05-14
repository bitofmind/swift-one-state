import Foundation
import Combine

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
    
    private init(box: (ContextBase) -> Box) {
        guard let context = ContextBase.current else {
            fatalError("Not allowed to access a ViewModel's property when not presented from a view")
        }
        
        self.context = context
        index = context.propertyIndex
        context.propertyIndex += 1
        
        if index == context.properties.count {
            context.properties.append(box(context))
        }
    }
    
    private var box: Box {
        context.properties[index] as! Box
    }
    
    public var wrappedValue: Value {
        get { box.get() }
        nonmutating set { box.set(newValue) }
    }
    
    public var projectedValue: Self { self }
}

public extension ModelProperty {
    init(wrappedValue: @escaping @autoclosure () -> Value) {
        self.init { _ in
            let subject = CurrentValueSubject<Value, Never>(wrappedValue())
            return Box(
                get: { subject.value },
                set: { subject.value = $0 },
                publisher: subject.eraseToAnyPublisher()
            )
        }
    }
}

public extension ModelProperty where Value: ViewModel {
    init<Root>(wrappedValue model: @escaping @autoclosure () -> Value, path: WritableKeyPath<Root, Value.State>) {
        self.init { context in
            let context = context as! Context<Root>
            let view = StoreView(context: context, path: path, access: .fromViewModel)
            let model = Value(view)
            
            model.retain()
            
            return Box(
                get: { model },
                set: { _ in fatalError("Mutating of view model propertied are not allowed, instead modify the state") },
                publisher: Empty().eraseToAnyPublisher()
            )
        }
    }
}

public extension ModelProperty {
    init<Root, Model: ViewModel>(wrappedValue model: @escaping @autoclosure () -> Model, path: WritableKeyPath<Root, Model.State?>) where Value == Model? {
        self.init { context in
            let context = context as! Context<Root>
            let rootView = StoreView(context: context, path: \.self, access: .fromViewModel)
            let view = rootView.storeView(for: path)
            var currentModel = view.map(Model.init)
            
            let publisher = context.stateDidUpdate
                .map { _ in
                    context.getCurrent(access: .fromViewModel, path: path) != nil
                }
                .merge(with: Just(currentModel != nil))
                .removeDuplicates()
                .map { _ in
                    rootView.storeView(for: path).map(Model.init)
                }
            
            publisher.sink { model in
                model?.context.retainFromView()
                currentModel?.release()
                currentModel = model
                model?.retain()
            }.store(in: &context.anyCancellables)

            return Box(
                get: { currentModel },
                set: { _ in fatalError("Mutating of view model propertied are not allowed, instead modify the state") },
                publisher: publisher.dropFirst().eraseToAnyPublisher()
            )
        }
    }
}

extension ModelProperty: Publisher {
    public typealias Output = Value
    public typealias Failure = Never
    
    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == Value, S.Failure == Never {
        box.publisher.receive(subscriber: subscriber)
    }
}

private extension ModelProperty {
    class Box {
        let get: () -> Value
        let set: (Value) -> ()
        let publisher: AnyPublisher<Value, Never>

        init(get: @escaping () -> (Value), set: @escaping (Value) -> (), publisher: AnyPublisher<Value, Never>) {
            self.get = get
            self.set = set
            self.publisher = publisher
        }
    }
}
