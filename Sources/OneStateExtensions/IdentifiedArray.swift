import OneState
import IdentifiedCollections
import OrderedCollections

extension IdentifiedArray: StateContainer where Element: Identifiable, Element.ID == ID  {
    public var structureValue: OrderedSet<Element.ID> { ids }
}

extension IdentifiedArray: ModelContainer where Element: Model&Identifiable, Element.State: Identifiable, Element.ID == ID, Element.State.ID == ID {
    public typealias StateContainer = IdentifiedArrayOf<Element.State>

    public static func modelContainer(from elements: [Element]) -> Self {
        .init(uniqueElements: elements)
    }

    public var stateContainer: StateContainer {
        StateContainer(uniqueElements: map { $0.nonObservableState })
    }

    public var models: [ModelElement] {
        elements
    }
}
