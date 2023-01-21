import Dependencies

/// Declares a dependency
///
/// A  model will get access to its [dependencies](https://github.com/pointfreeco/swift-dependencies)
/// by declaring `@ModelDependency` referring to a predefined `DependencyValues` value
///
///     struct MyServer {
///         var hello: (String) async -> String
///     }
///
///     extension DependencyValues {
///         var myServer: MyServer {
///             get { self[MyServerKey.self] }
///             set { self[MyServer.self] = newValue }
///         }
///
///         private enum MyServerKey: DependencyKey {
///             static let liveValue = { "Hello \($0)" }
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
/// `ModelDependency` takes a keyPath allowing to further
///  narrow in on a value:
///
///     @ModelDependency(\.myServer.hello) hello
///
///     func hello(_ name: String) async -> String {
///         let response = await hello(name)
///     }
///
@propertyWrapper @dynamicMemberLookup
public struct ModelDependency<Value> {
    let context: ContextBase
    let path: KeyPath<DependencyValues, Value>
    let index: Int

    public init(_ path: KeyPath<DependencyValues, Value>) {
        guard let context = ContextBase.current else {
            fatalError("ModelDependency can only be used from a Model with an injected store view.")
        }

        self.context = context
        self.path = path
        self.index = ThreadState.current.dependencyIndex
        ThreadState.current.dependencyIndex += 1
    }

    public var wrappedValue: Value {
        get {
            context.withDependencies {
                Dependency(self.path).wrappedValue
            }
        }
        nonmutating set {
            guard let path = path as? WritableKeyPath<DependencyValues, Value> else {
                fatalError("Dependency is not writable")
            }

            context.lock {
                context.dependencies.removeAll { $0.index == index }
                context.dependencies.append((index, {
                    $0[keyPath: path] = newValue
                }))
            }
        }
    }

    public var projectedValue: Self {
        return self
    }

    public func reset() {
        context.lock {
            context.dependencies.removeAll { $0.index == index }
        }
    }
}

extension ModelDependency: Sendable where Value: Sendable {}

extension ModelDependency: StoreViewProvider where Value: Model {
    public var storeView: StoreView<Value.State, Value.State, Write> {
        wrappedValue.storeView
    }
}
