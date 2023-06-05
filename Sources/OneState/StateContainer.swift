import Foundation
import CoreMedia

public protocol StateContainer {
    associatedtype Container = Self
    associatedtype Element
    associatedtype StructureValue: Equatable

    static func elementKeyPaths(for container: Container) -> [WritableKeyPath<Container, Element>]
    static func structureValue(for container: Container) -> StructureValue
}

public protocol DefaultedStateContainer: StateContainer {
    static func defaultContainer() -> Container
}

extension StateContainer where Element == Self {
    public static func elementKeyPaths(for container: Self) -> [WritableKeyPath<Self, Self>] { [\.self] }
}

public enum IdentityStateContainer<State>: StateContainer {
    public struct AlwaysEqual: Equatable {}
    public static func elementKeyPaths(for container: State) -> [WritableKeyPath<State, State>] { [\.self] }
    public static func structureValue(for container: State) -> AlwaysEqual { .init() }
}

extension Optional: DefaultedStateContainer {
    public static func defaultContainer() -> Self { .none }
    public static func elementKeyPaths(for container: Self) -> [WritableKeyPath<Self, Wrapped>] {
        container.map { [\.[unwrapFallback: UnwrapFallback(value: $0)]] } ?? []
    }

    public static func structureValue(for container: Self) -> AnyHashable? {
        container.map(anyHashable)
    }
}

public extension MutableCollection {
    static func elementKeyPaths<ID: Hashable>(for container: Self, idPath: KeyPath<Element, ID>) -> [WritableKeyPath<Self, Element>] {
        container.indices.map { index in
            let state = container[index]
            let cursor = Cursor(idPath: idPath, id: state[keyPath: idPath], index: index, fallback: state)
            return \.[cursor: cursor]
        }
    }
}

public extension RangeReplaceableCollection {
    static func defaultContainer() -> Self { Self() }
}

public extension MutableCollection where Element: Identifiable {
    static func elementKeyPaths(for container: Self) -> [WritableKeyPath<Self, Element>] {
        elementKeyPaths(for: container, idPath: \.id)
    }

    static func structureValue(for container: Self) -> [Element.ID] { container.map(\.id) }
}

extension Array: StateContainer&DefaultedStateContainer where Element: Identifiable {}

private extension Optional {
    subscript (unwrapFallback fallback: UnwrapFallback<Wrapped>) -> Wrapped {
        get {
            self ?? fallback.value
        }
        set {
            guard self != nil else { return }
            
            fallback.value = newValue
            self = newValue
        }
    }
}

private extension MutableCollection {
    subscript<ID: Hashable>(cursor cursor: Cursor<Element, ID, Index>) -> Element {
        get {
            if cursor.index >= startIndex && cursor.index < endIndex {
                let element = self[cursor.index]
                if element[keyPath: cursor.idPath] == cursor.id {
                    return element
                }
            }

            return first { $0[keyPath: cursor.idPath] == cursor.id } ?? cursor.fallback
        }
        set {
            if cursor.index >= startIndex && cursor.index < endIndex {
                if self[cursor.index][keyPath: cursor.idPath] == cursor.id {
                    self[cursor.index] = newValue
                    return
                }
            }
            
            guard let index = firstIndex(where: { $0[keyPath: cursor.idPath] == cursor.id }) else { return }
            
            cursor.fallback = newValue
            self[index] = newValue
        }
    }
}

// Crash in key path append if using struct instead of class
private class UnwrapFallback<Value>: Hashable, @unchecked Sendable {
    var value: Value
    
    init(value: Value) {
        self.value = value
    }

    var id: AnyHashable {
        anyHashable(from: value)
    }
    
    static func == (lhs: UnwrapFallback, rhs: UnwrapFallback) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

private func anyHashable(from value: Any) -> AnyHashable {
    (value as? any Identifiable)?.anyHashable ?? AnyHashable(ObjectIdentifier(Any.self))
}

private extension Identifiable {
    var anyHashable: AnyHashable { AnyHashable(id) }
}

// Crash in key path append if using struct instead of class
private class Cursor<Value, ID: Hashable, Index>: Hashable, @unchecked Sendable  {
    let idPath: KeyPath<Value, ID>
    let id: ID
    let index: Index
    var fallback: Value
    
    init(idPath: KeyPath<Value, ID>, id: ID, index: Index, fallback: Value) {
        self.idPath = idPath
        self.id = id
        self.index = index
        self.fallback = fallback
    }
    
    static func == (lhs: Cursor, rhs: Cursor) -> Bool {
        lhs.idPath == rhs.idPath && lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(idPath)
        hasher.combine(id)
    }
}
