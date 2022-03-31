import SwiftUI

@propertyWrapper
public struct ModelEnvironment<Value>: DynamicProperty {
    let context: ContextBase?
    @Environment(\.modelEnvironments) private var modelEnvironments
    let fallbackValue: (() -> Value)?
    
    final class Shared: ObservableObject {
        var fallbackValue: Value?
    }
    
    @StateObject var shared = Shared()

    public init() {
        context = ContextBase.current
        fallbackValue = nil
    }
    
    public init(wrappedValue: @escaping @autoclosure () -> Value) {
        context = ContextBase.current
        fallbackValue = wrappedValue
    }
    
    public func update() {
        shared.fallbackValue = shared.fallbackValue ?? fallbackValue?()
    }
    
    public var wrappedValue: Value {
        get {
            (contextBinding ?? environmentBinding).get()
        }
        nonmutating set {
            (contextBinding ?? environmentBinding).set(newValue)
        }
    }
    
    public var projectedValue: Self {
        return self
    }
    
    public var binding: Binding<Value> {
        .init {
            wrappedValue
        } set: {
            wrappedValue = $0
        }
    }
}

public extension View {
    func modelEnvironment<Value>(get: @escaping () -> Value, set: @escaping (Value) -> Void = { _ in }) -> some View {
        modifier(EnvironmentValuesModifier(value: .init(get: get, set: set)))
    }

    func modelEnvironment<Value>(_ value: Value) -> some View {
        modelEnvironment(.constant(value))
    }
    
    func modelEnvironment<Value>(_ value: Binding<Value>) -> some View {
        modelEnvironment(get: { value.wrappedValue }, set: { value.wrappedValue = $0 })
    }
}

private extension ModelEnvironment {
    var environmentBinding: EnvironmentBinding<Value> {
        let binding = modelEnvironments[ObjectIdentifier(Value.self)]
            .map {
                $0 as! EnvironmentBinding<Value>
            } ?? shared.fallbackValue.map { value in
                EnvironmentBinding(get: { value }, set: { _ in })
            }
        
        guard let binding = binding else {
            fatalError("No environment has been set for `\(Value.self)`")
        }
        
        return binding
    }
    
    var contextBinding: EnvironmentBinding<Value>? {
        guard let context = context else {
            return nil
        }

        var binding = context.environments[ObjectIdentifier(Value.self)].map { $0 as! EnvironmentBinding<Value> }

        if binding == nil, let fallback = fallbackValue {
            var value = fallback()
            binding = .init {
                value
            } set: {
                value = $0
            }
            context.environments[ObjectIdentifier(Value.self)] = binding
        }
        
        guard let binding = binding else {
            if ContextBase.current != nil {
                fatalError("Not allowed to access a ViewModel's environment from init()")
            } else if context.hasBeenRemoved {
                fatalError("The context holding the environment has been removed and is no longer active in any view")
            } else if context.isFullyInitialized {
                fatalError("No environment has been set for `\(Value.self)`")
            } else {
                fatalError("Not allowed to access a ViewModel's environment when not presented from a view")
            }
        }
        
        return binding
    }
}

typealias Environments = [ObjectIdentifier: Any]

extension EnvironmentValues {
    var modelEnvironments: Environments {
      get { self[ModelEnvironmentsKey.self] }
      set { self[ModelEnvironmentsKey.self] = newValue }
    }
}

private struct ModelEnvironmentsKey: EnvironmentKey {
    static let defaultValue: Environments = [:]
}

private struct EnvironmentValuesModifier<T>: ViewModifier {
    @Environment(\.modelEnvironments) var modelEnvironments
    var value: EnvironmentBinding<T>
    
    var environments: Environments {
        var environments = modelEnvironments
        environments[(ObjectIdentifier(T.self))] = value
        return environments
    }
    
    func body(content: Content) -> some View {
        content
            .environment(\.modelEnvironments, environments)
    }
}

struct EnvironmentBinding<Value> {
    let get: () -> Value
    let set: (Value) -> Void
}
