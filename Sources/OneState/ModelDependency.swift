/// Declares a dependency
///
/// A  model access external depenencies by declaring `@ModelDependency`
/// refering to a predefined `ModelDependencyValues` value
///
///     struct MyServer {
///         var hello: (String) async -> String
///     }
///
///     private enum MyServerKey: ModelDependencyKey {
///         static let defaultValue = { "Hello \($0)" }
///     }
///
///     extension ModelDependencyValues {
///         var myServer: MyServer {
///             get { self[MyServerKey.self] }
///             set { self[MyServer.self] = newValue }
///         }
///     }
///
///     struct MyModel: Model {
///         @ModelDependency(\.myServer) myServer
///
///         func hello(_ name: String) async -> String {
///             let response = await myServer.hello(name)
///         }
///     }
///
///   `ModelDependency` takes a keyPath allowing to furhter
///   narrow in on a value:
///
///     @ModelDependency(\.myServer.hello) hello
///
///     func hello(_ name: String) async -> String {
///         let response = await hello(name)
///     }
///
@propertyWrapper @dynamicMemberLookup
public struct ModelDependency<Value> {
    let dependencies: ModelDependencyValues
    let path: KeyPath<ModelDependencyValues, Value>

    public init(_ path: KeyPath<ModelDependencyValues, Value>) {
        guard let context = ContextBase.current else {
            fatalError("ModelDependency can only be used from a Model with an injected store view.")
        }

        dependencies = ModelDependencyValues {
            context.dependencyValue(key: $0)
        } set: {
            context.environments[$0] = $1
        }
        self.path = path
    }

    public var wrappedValue: Value {
        get {
            dependencies[keyPath: path]
        }
        nonmutating set {
            guard let path = path as? WritableKeyPath<ModelDependencyValues, Value> else {
                fatalError("Dependency is not writable")
            }
            var d = dependencies
            d[keyPath: path] = newValue
        }
    }
}

extension ModelDependency: Sendable where Value: Sendable {}

extension ModelDependency: StoreViewProvider where Value: Model {
    public var storeView: StoreView<Value.State, Value.State, Write> {
        wrappedValue.storeView
    }
}

extension ContextBase {
    func dependencyValue(key: ObjectIdentifier) -> Any? {
        var value = environments[key]

        var parent = self.parent
        while value == nil, let p = parent {
            value = p.environments[key]
            parent = p.parent
        }

        return value
    }
}
