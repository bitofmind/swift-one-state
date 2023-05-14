import Foundation

public protocol ModelContainer {
    associatedtype ModelElement: Model = Self
    associatedtype StateContainer: OneState.StateContainer = IdentityStateContainer<ModelElement.State> where ModelElement.State == StateContainer.Element
    typealias Container = StateContainer.Container
    
    static func modelContainer(from elements: [ModelElement]) -> Self
    var stateContainer: Container { get }
    var models: [ModelElement] { get }
}

public typealias ContainerStoreViewProvider<State: StateContainer, Access> = StoreViewProvider<State, Access> where State.Container == State

public extension ModelContainer {
    init(_ provider: some StoreViewProvider<Container, Write>) {
        let view = provider.storeView
        let containerPath = view.path
        let containerView = StoreView(context: view.context, path: containerPath, access: view.access)
        let container = view.context.value(for: containerView.path, access: containerView.access, comparable: StructureComparableValue<StateContainer>.self)
        let elementPaths = StateContainer.elementKeyPaths(for: container)
        let models = StoreAccess.with(view.access) {
            elementPaths.map { path in
                ModelElement(containerView.storeView(for: path))
            }
        }

        self = Self.modelContainer(from: models)

        view.observeContainer(ofType: type(of: self), atPath: \.self)
    }

    init<Provider: StoreViewProvider>(_ provider: Provider) where Provider.State == StateModel<Self>, Provider.Access == Write {
        self.init(provider.storeView(for: \.wrappedValue))
    }
}

extension Model where StateContainer == IdentityStateContainer<State>, ModelElement == Self {
    public static func modelContainer(from elements: [Self]) -> Self {
        elements[0]
    }

    public var stateContainer: Container {
        nonObservableState
    }

    public var models: [ModelElement] {
        [self]
    }
}

extension Optional: ModelContainer where Wrapped: Model {
    public typealias StateContainer = Wrapped.State?

    public static func modelContainer(from elements: [Wrapped]) -> Self {
        elements.first
    }

    public var stateContainer: StateContainer {
        map { $0.nonObservableState }
    }

    public var models: [ModelElement] {
        map { [$0] } ?? []
    }
}

extension Collection where Element: Model, Element.State: Identifiable, Element: Identifiable {
    public typealias StateContainer = [Element.State]

    public var stateContainer: StateContainer {
        map { $0.nonObservableState }
    }

    public var models: [Element] {
        map { $0 }
    }
}

extension RangeReplaceableCollection where Element: Model, Element.State: Identifiable, Element: Identifiable {
    public static func modelContainer(from elements: [Element]) -> Self {
        Self(elements)
    }
}

extension Array: ModelContainer where Element: Model, Element.State: Identifiable, Element: Identifiable {
    public static func modelContainer(from elements: [Element]) -> Self { elements }
    public var models: [ModelElement] { self }
}

extension Optional {
    subscript<T> (unwrap path: KeyPath<Wrapped, T>) -> T? {
        self?[keyPath: path]
    }

    subscript<T> (unwrap path: KeyPath<Wrapped, T?>) -> T? {
        self?[keyPath: path]
    }

    subscript<T> (unwrap path: WritableKeyPath<Wrapped, T>) -> T? {
        get {
            self?[keyPath: path]
        }
        set {
            if let value = newValue {
                self?[keyPath: path] = value
            }
        }
    }

    subscript<T> (unwrap path: WritableKeyPath<Wrapped, T?>) -> T? {
        get {
            self?[keyPath: path]
        }
        set {
            self?[keyPath: path] = newValue
        }
    }
}
