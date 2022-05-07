import SwiftUI

/// Declares a dependency on an enviroment
///
/// A view model access it's enviroment, i.e. external depenencies,
/// by declaring @ModelEnvironment with a matching type
///
///     struct MyServer {
///         var hello: () async -> ()
///     }
///
///     struct MyModel: ViewModel {
///         @ModelEnvironment myServer: MyServer
///
///         func onAppear() async {
///             await myServer.hello()
///         }
///     }
///
/// An enviroment is set (injected) via a SwiftUI View's
///  `modelEnvironment()` method, typically from the root view
///
///     $store.viewModel(AppModel())
///         .modelEnvironment(MyServer(
///             hello: { print("Hello") }
///         ))
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
            let value: Value?
            if let context = context {
                precondition(ContextBase.current == nil, "Not allowed to access a ViewModel's environment from init()")
                precondition(!context.hasBeenRemoved, "The context holding the environment has been removed and is no longer active in any view")
                
                value = context.environmentValue(fallbackValue: fallbackValue)
            } else {
                value = modelEnvironments[key].map { $0 as! Value } ?? shared.fallbackValue
            }

            guard let value = value else {
                fatalError("No environment has been set for `\(Value.self)`")
            }
            
            return value
        }
        nonmutating set {
            guard let context = context else {
                fatalError("You are not allowed to modify a `ModelEnvironment` when ussed in a SwiftUI view")
            }
            
            context.localEnvironments[key] = newValue
        }
    }
    
    public var projectedValue: Self {
        return self
    }
}

public extension View {
    /// Set/injects an environment that can be accesses from a view model's `@ModeEnvironment` property
    func modelEnvironment<Value>(_ value: Value) -> some View {
        modifier(EnvironmentValuesModifier(value: value))
    }
}

private extension ModelEnvironment {
    var key: ObjectIdentifier { .init(Value.self) }
}

extension ContextBase {
    func environmentValue<Value>(fallbackValue: (() -> Value)?) -> Value? {
        let key = ObjectIdentifier(Value.self)
        
        var value = localEnvironments[key] ?? viewEnvironments[key]
        
        var parent = self.parent
        while value == nil, let p = parent {
            value = p.localEnvironments[key]
            parent = p.parent
        }

        if value == nil, let fallback = fallbackValue {
            value = fallback()
            localEnvironments[key] = value
        }
        
        return value.map { $0 as! Value }
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

private struct EnvironmentValuesModifier<Value>: ViewModifier {
    @Environment(\.modelEnvironments) var modelEnvironments
    var value: Value
    
    var environments: Environments {
        var environments = modelEnvironments
        environments[(ObjectIdentifier(Value.self))] = value
        return environments
    }
    
    func body(content: Content) -> some View {
        content
            .environment(\.modelEnvironments, environments)
    }
}
