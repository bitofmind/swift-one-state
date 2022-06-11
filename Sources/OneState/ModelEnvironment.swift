/// Declares a dependency on an enviroment
///
/// A  model access it's enviroment, i.e. external depenencies,
/// by declaring @ModelEnvironment with a matching type
///
///     struct MyServer {
///         var hello: () async -> ()
///     }
///
///     struct MyModel: Model {
///         @ModelEnvironment myServer: MyServer
///
///         func onActivate() async {
///             await myServer.hello()
///         }
///     }
@propertyWrapper
public struct ModelEnvironment<Value> {
    let context: ContextBase
    let fallbackValue: (() -> Value)?

    public init() {
        guard let context = ContextBase.current else {
            fatalError("ModelEnvironment can only be used from a Model with an injected view.")
        }

        self.context = context
        fallbackValue = nil
    }
    
    public init(wrappedValue: @escaping @autoclosure () -> Value) {
        guard let context = ContextBase.current else {
            fatalError("ModelEnvironment can only be used from a Model with an injected view.")
        }

        self.context = context
        fallbackValue = wrappedValue
    }

    public var wrappedValue: Value {
        get {
            precondition(!context.hasBeenRemoved, "The context holding the environment has been removed and is no longer active")

            guard let value = context.environmentValue(fallbackValue: fallbackValue) else {
                fatalError("No environment has been set for `\(Value.self)`")
            }
            
            return value
        }
        nonmutating set {
            context.environments[key] = newValue
        }
    }
    
    public var projectedValue: Self {
        return self
    }
}

private extension ModelEnvironment {
    var key: ObjectIdentifier { .init(Value.self) }
}

extension ContextBase {
    func environmentValue<Value>(fallbackValue: (() -> Value)?) -> Value? {
        let key = ObjectIdentifier(Value.self)
        
        var value = environments[key]
        
        var parent = self.parent
        while value == nil, let p = parent {
            value = p.environments[key]
            parent = p.parent
        }

        if value == nil, let fallback = fallbackValue {
            value = fallback()
            environments[key] = value
        }
        
        return value.map { $0 as! Value }
    }
}

typealias Environments = [ObjectIdentifier: Any]

