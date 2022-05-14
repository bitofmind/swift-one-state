import Foundation

public protocol ModelContainer {
    associatedtype ModelElement: ViewModel = Self
    associatedtype StateContainer = ModelElement.State
    
    static func modelContainer(from elements: [ModelElement]) -> Self
    var stateContainer: StateContainer { get }
}

extension ViewModel where StateContainer == State, ModelElement == Self {
    public static func modelContainer(from elements: [Self]) -> Self {
        elements[0]
    }

    public var stateContainer: StateContainer {
        value(for: \.self)
    }
}

extension Optional: ModelContainer where Wrapped: ViewModel {
    public typealias StateContainer = Wrapped.State?

    public static func modelContainer(from elements: [Wrapped]) -> Self {
        elements.first
    }

    public var stateContainer: StateContainer {
        map { $0.value(for: \.self) }
    }
}

extension Array: ModelContainer where Element: ViewModel, Element.State: Identifiable, Element: Identifiable {
    public typealias StateContainer = [Element.State]

    public static func modelContainer(from elements: [Element]) -> Self {
        elements
    }

    public var stateContainer: StateContainer {
        map { $0.value(for: \.self) }
    }
}
