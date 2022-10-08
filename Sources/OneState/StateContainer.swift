import Foundation
import CoreMedia

public protocol StateContainer {
    associatedtype Element

    var elementKeyPaths: [WritableKeyPath<Self, Element>] { get }
    
    static func hasSameStructure(lhs: Self, rhs: Self) -> Bool
}

extension StateContainer where Element == Self {
    public var elementKeyPaths: [WritableKeyPath<Self, Self>] { [\.self] }
    
    public static func hasSameStructure(lhs: Self, rhs: Self) -> Bool { true }
}

extension Optional: StateContainer {
    public var elementKeyPaths: [WritableKeyPath<Self, Wrapped>] {
        map { [\.[unwrapFallback: UnwrapFallback(value: $0)]] } ?? []
    }
    
    public static func hasSameStructure(lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.some, .some), (.none, .none): return true
        case (.some, .none), (.none, .some): return false
        }
    }
}

public extension MutableCollection {
    func elementKeyPaths<ID: Hashable>(idPath: KeyPath<Element, ID>) -> [WritableKeyPath<Self, Element>] {
        indices.map { index in
            let state = self[index]
            let cursor = Cursor(idPath: idPath, id: state[keyPath: idPath], index: index, fallback: state)
            return \.[cursor: cursor]
        }
    }
    
    static func hasSameStructure<ID: Hashable>(lhs: Self, rhs: Self, id: (Element) -> ID) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).first { id($0) != id($1) } == nil
    }
}

public extension MutableCollection where Element: Identifiable {
    var elementKeyPaths: [WritableKeyPath<Self, Element>] {
        elementKeyPaths(idPath: \.id)
    }
    
    static func hasSameStructure(lhs: Self, rhs: Self) -> Bool {
        hasSameStructure(lhs: lhs, rhs: rhs, id: \.id)
    }
}

extension Array: StateContainer where Element: Identifiable {}

public extension StoreViewProvider {
    func containerStoreViewElements<Container: MutableCollection>(for path: KeyPath<State, Container>) -> [StoreView<Root, Container.Element, Read>] where Container.Element: Identifiable {
        let containerView = storeView(for: path)
        let container = containerView.value(for: \.self, isSame: Container.hasSameStructure)
        return container.elementKeyPaths.map { path in
            containerView.storeView(for: path)
        }
    }

    func containerStoreViewElements<Container: StateContainer>(for path: KeyPath<State, Container>) -> [StoreView<Root, Container.Element, Read>] {
        let containerView = storeView(for: path)
        let container = containerView.value(for: \.self, isSame: Container.hasSameStructure)
        return container.elementKeyPaths.map { path in
            containerView.storeView(for: path)
        }
    }

    func storeView<T>(for path: KeyPath<State, T?>) -> StoreView<Root, T, Read>? {
        containerStoreViewElements(for: path).first
    }
}

public extension StoreViewProvider where Access == Write {
    func containerStoreViewElements<Container: MutableCollection>(for path: WritableKeyPath<State, Container>) -> [StoreView<Root, Container.Element, Write>] where Container.Element: Identifiable {
        let containerView = storeView(for: path)
        let container = containerView.value(for: \.self, isSame: Container.hasSameStructure)
        return container.elementKeyPaths.map { path in
            containerView.storeView(for: path)
        }
    }
    
    func containerStoreViewElements<Container: StateContainer>(for path: WritableKeyPath<State, Container>) -> [StoreView<Root, Container.Element, Write>] {
        let containerView = storeView(for: path)
        let container = containerView.value(for: \.self, isSame: Container.hasSameStructure)
        return container.elementKeyPaths.map { path in
            containerView.storeView(for: path)
        }
    }

    func storeView<T>(for path: WritableKeyPath<State, T?>) -> StoreView<Root, T, Write>? {
        containerStoreViewElements(for: path).first
    }
    
    subscript<C>(dynamicMember keyPath: WritableKeyPath<State, C>) -> [IdentifiableStoreView<Root, C.Element, Write, C.Element.ID>] where C: MutableCollection, C.Element: Identifiable {
        containerStoreViewElements(for: keyPath).map { view in
            IdentifiableStoreView(storeView: view, idPath: \.id)
        }
    }
    
    func id<ID>(_ idPath: KeyPath<State.Element, ID>) -> [IdentifiableStoreView<Root, State.Element, Write, ID>] where State: MutableCollection, ID: Hashable {
        let container = value(for: \.self, isSame: {
            State.hasSameStructure(lhs: $0, rhs: $1, id: { $0[keyPath: idPath] })
        })
        return container.elementKeyPaths(idPath: idPath).map { path in
            let view = storeView(for: path)
            return IdentifiableStoreView(storeView: view, idPath: idPath)
        }
    }
}
    
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
