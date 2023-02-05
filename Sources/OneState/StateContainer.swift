import Foundation
import CoreMedia

public protocol StateContainer {
    associatedtype Element
    associatedtype StructureValue: Equatable

    var elementKeyPaths: [WritableKeyPath<Self, Element>] { get }
    var structureValue: StructureValue { get }
}

extension StateContainer where Element == Self {
    public var elementKeyPaths: [WritableKeyPath<Self, Self>] { [\.self] }
}

extension Optional: StateContainer {
    public var elementKeyPaths: [WritableKeyPath<Self, Wrapped>] {
        map { [\.[unwrapFallback: UnwrapFallback(value: $0)]] } ?? []
    }

    public var structureValue: Bool { self != nil }
}

public extension MutableCollection {
    func elementKeyPaths<ID: Hashable>(idPath: KeyPath<Element, ID>) -> [WritableKeyPath<Self, Element>] {
        indices.map { index in
            let state = self[index]
            let cursor = Cursor(idPath: idPath, id: state[keyPath: idPath], index: index, fallback: state)
            return \.[cursor: cursor]
        }
    }
}

public extension MutableCollection where Element: Identifiable {
    var elementKeyPaths: [WritableKeyPath<Self, Element>] {
        elementKeyPaths(idPath: \.id)
    }

    var structureValue: [Element.ID] { map(\.id) }
}

extension Array: StateContainer where Element: Identifiable {}
    
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

// Crash in keypath append if using struct instead of class
private class UnwrapFallback<Value>: Hashable, @unchecked Sendable {
    var value: Value
    
    init(value: Value) {
        self.value = value
    }
    
    static func == (lhs: UnwrapFallback, rhs: UnwrapFallback) -> Bool {
        return true
    }
    
    func hash(into hasher: inout Hasher) { }
}

// Crash in keypath append if using struct instead of class
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
