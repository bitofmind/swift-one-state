import Foundation

public protocol ModelContainer {
    associatedtype ModelElement: Model = Self
    associatedtype StateContainer = ModelElement.State
    
    static func modelContainer(from elements: [ModelElement]) -> Self
    var stateContainer: StateContainer { get }
    var models: [ModelElement] { get }
}

public extension ModelContainer {
    init<Provider: StoreViewProvider>(_ viewStore: Provider) where Provider.State == StateModel<Self>, Provider.Access == Write, StateContainer: OneState.StateContainer, StateContainer.Element == ModelElement.State {
        let view = viewStore.storeView
        let containerPath = view.path(\.wrappedValue)
        let containerView = StoreView(context: view.context, path: containerPath, access: view.access)
        let container = view.context.value(for: containerView.path, access: containerView.access, comparable: StructureComparableValue.self)
        let elementPaths = container.elementKeyPaths
        let models = StoreAccess.with(view.access) {
            elementPaths.map { path in
                ModelElement(containerView.storeView(for: path))
            }
        }

        view.observeContainer(atPath: \.self)

        self = Self.modelContainer(from: models)
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
