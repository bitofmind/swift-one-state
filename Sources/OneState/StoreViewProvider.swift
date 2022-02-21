import SwiftUI
import Combine

public protocol StoreViewProvider {
    associatedtype Root
    associatedtype State

    var storeView: StoreView<Root, State> { get }
}

public extension StoreViewProvider {
    func value<T>(for keyPath: KeyPath<State, T>, isSame: @escaping (T, T) -> Bool) -> T {
        let view = self.storeView
        return view.context.value(for: view.path.appending(path: keyPath), access: view.access, isSame: isSame)
    }
    
    func value<T: Equatable>(for keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath, isSame: ==)
    }

    func value<T>(for keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath, isSame: { _, _ in false })
    }
    
    func storeView<T>(for keyPath: WritableKeyPath<State, T>) -> StoreView<Root, T> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }
    
    func storeView<T>(for keyPath: WritableKeyPath<State, T?>) -> StoreView<Root, T>? {
        func isSame(lhs: T?, rhs: T?) -> Bool {
            switch (lhs, rhs) {
            case (.some, .some), (.none, .none): return true
            case (.some, .none), (.none, .some): return false
            }
        }
        
        let view = storeView
        let optionPath = view.path(keyPath)
        
        // If an access of `fromViewModel` goes via an optional path we need to change it to `fromView` to make sure view's are notified of changes in e.g. modals
        var optionalAccess = view.access
        if optionalAccess == .fromViewModel {
            optionalAccess = .fromView
        }
        
        guard let initial = view.context.value(for: optionPath, access: optionalAccess, isSame: isSame) else {
            return nil
        }
        
        let unwrapPath = optionPath.appending(path: \T?[unwrapFallback: UnwrapFallback(initial)])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }
}

public extension StoreViewProvider {
    func setValue<T>(_ value: T, at keyPath: WritableKeyPath<State, Writable<T>>) {
        let view = storeView
        return view.context[keyPath: view.path(keyPath), access: view.access] = .init(wrappedValue: value)
    }
}

public extension StoreViewProvider where State: Equatable {
    var value: State {
        value(for: \.self)
    }
}

public extension StoreViewProvider {
    subscript<T>(dynamicMember keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath)
    }

    subscript<T: Equatable>(dynamicMember keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath)
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, T>) -> StoreView<Root, T> {
        storeView(for: keyPath)
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, Writable<T>>) -> Binding<T> {
        let storeView = self.storeView
        return .init {
            storeView.value(for: keyPath).wrappedValue
        } set: { newValue in
            storeView.setValue(newValue, at: keyPath)
        }
    }
    
    subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, Writable<T>>) -> Binding<T> {
        let storeView = self.storeView
        return .init {
            storeView.value(for: keyPath).wrappedValue
        } set: { newValue in
            storeView.setValue(newValue, at: keyPath)
        }
    }
    
    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, Writable<T?>>) -> Binding<StoreView<Root, T>?> {
        let view = self.storeView
        return .init {
            view.storeView(for: keyPath.appending(path: \.wrappedValue))
        } set: { newValue in
            view.setValue(newValue.map {
                $0.context[keyPath: $0.path, access: view.access]
            }, at: keyPath)
        }
    }
    
    subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, Writable<T?>>) -> Binding<StoreView<Root, T>?> {
        let view = self.storeView
        return .init {
            view.storeView(for: keyPath.appending(path: \.wrappedValue))
        } set: { newValue in
            view.setValue(newValue.map {
                $0.context[keyPath: $0.path, access: view.access]
            }, at: keyPath)
        }
    }
    
    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, T?>) -> StoreView<Root, T>? {
        storeView(for: keyPath)
    }

    subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, T?>) -> StoreView<Root, T>? {
        storeView(for: keyPath)
    }

    subscript<S, T: Equatable>(dynamicMember keyPath: WritableKeyPath<S, T>) -> StoreView<Root, T>? where State == S? {
        storeView(for: \.self)?.storeView(for: keyPath)
    }

    subscript<S, T: Equatable>(dynamicMember keyPath: WritableKeyPath<S, T?>) -> StoreView<Root, T>? where State == S? {
        storeView(for: \.self)?.storeView(for: keyPath)
    }

    func id<T>(_ keyPath: KeyPath<State.Element, T>) -> [IdentifiableStoreView<Root, State.Element, T>] where State: MutableCollection, T: Hashable, State.Index: Hashable {
        func isSame(lhs: State, rhs: State) -> Bool {
            // lhs.map(\.id) == rhs.map(\.id)
            guard lhs.count == rhs.count else { return false }
            
            //return zip(lhs, rhs).reduce(true) { $0 && $1.0.id == $1.1.id }
            for (l, r) in zip(lhs, rhs) {
                if l[keyPath: keyPath] != r[keyPath: keyPath] {
                    return false
                }
            }
            
            return true
        }

        let view = storeView
        
        // If an access of `fromViewModel` goes via an optional path we need to change it to `fromView` to make sure view's are notified of array changes in e.g. a ForEach
        var arrayAccess = view.access
        if arrayAccess == .fromViewModel {
            arrayAccess = .fromView
        }

        return view.context.value(for: view.path(\.self), access: arrayAccess, isSame: isSame).map {
            $0[keyPath: keyPath]
        }.compactMap { id in
            storeView(for: \State[pathAndId: PathAndId(path: keyPath, id: id)]).map {
                .init(context: $0.context, path: $0.path, idPath: keyPath, access: view.access)
            }
        }
    }
    
//    subscript<C>(dynamicMember keyPath: WritableKeyPath<State, C>) -> [StoreView<Root, C.Element>] where C: MutableCollection, C: Equatable, C.Index: Hashable {
//        context.value(for: path(keyPath)).indices.compactMap { index in
//            storeView(for: keyPath.appending(path: \C[safe: index]))
//        }
//    }

    subscript<C>(dynamicMember keyPath: WritableKeyPath<State, C>) -> [IdentifiableStoreView<Root, C.Element, C.Element.ID>] where C: MutableCollection, C: Equatable, C.Element: Identifiable, C.Index: Hashable {
        storeView(for: keyPath).id(\.id)
    }
}

//extension StoreViewProvider {
////    var context: Context<Root> { storeView.context }
////    var path: WritableKeyPath<Root, State> { storeView.path }
//
//    func path<T>(_ keyPath: WritableKeyPath<State, T>) -> WritableKeyPath<Root, T>{
//        storeView.path.appending(path: keyPath)
//    }
//}

//extension MutableCollection {
//    subscript (safe index: Index) -> Element? {
//        get {
//            guard indices.contains(index) else { return nil }
//            return self[index]
//        }
//        set {
//            guard let value = newValue else { return }
//            self[index] = value
//        }
//    }
//}

struct PathAndId<Value, ID: Hashable>: Hashable {
    var path: KeyPath<Value, ID>
    var id: ID
}

extension MutableCollection {
    subscript<ID: Hashable>(pathAndId pathAndId: PathAndId<Element, ID>) -> Element? {
        get {
            first { $0[keyPath: pathAndId.path] == pathAndId.id }
        }
        set {
            guard let value = newValue, let index = firstIndex(where: { $0[keyPath: pathAndId.path] == pathAndId.id }) else { return }
            self[index] = value
        }
    }
}

extension WritableKeyPath {
    func unwrapped<T>(initial: T) -> WritableKeyPath<Root, T> where Value == T? {
        appending(path: \T?[unwrapFallback: UnwrapFallback(initial)])
    }
}

final class UnwrapFallback<Value>: Hashable {
    var value: Value
    
    init(_ value: Value) {
        self.value = value
    }

    static func == (lhs: UnwrapFallback, rhs: UnwrapFallback) -> Bool {
        return true
    }
    
    func hash(into hasher: inout Hasher) { }
}

extension Optional {
    subscript (unwrapFallback fallback: UnwrapFallback<Wrapped>) -> Wrapped {
        get {
            guard let self = self else {
                return fallback.value
            }
            return self
        }
        set {
            fallback.value = newValue
            guard self != nil else { return }
            
            self = newValue
        }
    }
}
