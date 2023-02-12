import Foundation

public protocol ModelContainer {
    associatedtype ModelElement: Model = Self
    associatedtype StateContainer = ModelElement.State
    
    static func modelContainer(from elements: [ModelElement]) -> Self
    var stateContainer: StateContainer { get }
    var models: [ModelElement] { get }
}

public extension ModelContainer {
    init<Provider: StoreViewProvider>(_ provider: Provider) where Provider.State == StateContainer, Provider.Access == Write, StateContainer: OneState.StateContainer, StateContainer.Element == ModelElement.State {
        let view = provider.storeView
        let containerPath = view.path
        let containerView = StoreView(context: view.context, path: containerPath, access: view.access)
        let container = view.context.value(for: containerView.path, access: containerView.access, comparable: StructureComparableValue.self)
        let elementPaths = container.elementKeyPaths
        let models = StoreAccess.with(view.access) {
            elementPaths.map { path in
                ModelElement(containerView.storeView(for: path))
            }
        }

        self = Self.modelContainer(from: models)

        view.observeContainer(ofType: type(of: self), atPath: \.self)
    }

    init<Provider: StoreViewProvider>(_ storeView: Provider) where Provider.State == StateModel<Self>, Provider.Access == Write, StateContainer: OneState.StateContainer, StateContainer.Element == ModelElement.State {
        self.init(storeView.storeView(for: \.wrappedValue))
    }
}

extension Model where StateContainer == State, ModelElement == Self {
    public static func modelContainer(from elements: [Self]) -> Self {
        elements[0]
    }

    public var stateContainer: StateContainer {
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

extension Array: ModelContainer where Element: Model, Element.State: Identifiable, Element: Identifiable {
    public typealias StateContainer = [Element.State]

    public static func modelContainer(from elements: [Element]) -> Self {
        elements
    }

    public var stateContainer: StateContainer {
        map { $0.nonObservableState }
    }

    public var models: [ModelElement] {
        self
    }
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
