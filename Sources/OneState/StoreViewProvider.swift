import SwiftUI
import Combine

/// Conforming types exposes a view into the store holding its state
///
/// Typically conforming types are also declared as `@dynamicMemberLookup`
/// to allow convienent access to a stores states members.
///
/// Most common when accessing a sub state is that you get anothter store view
/// back instead of the raw value. This allows you to construct viewModels with direct
/// view into a store:
///
///     provider.myState.viewModel(MyModel())
public protocol StoreViewProvider {
    associatedtype Root
    associatedtype State

    var storeView: StoreView<Root, State> { get }
}

public extension StoreViewProvider where State: Equatable {
    var publisher: AnyPublisher<State, Never> {
        let view = self.storeView
        
        return storeView.context.stateDidUpdate.compactMap { update -> State? in
            let stateUpdate = StateUpdate(view: view, update: update)
            
            let current = stateUpdate.current
            let previous = stateUpdate.previous

            return  previous != current ? current : nil
        }.merge(with: Just(value)).eraseToAnyPublisher()
    }
    
    @available(iOS 15, macOS 12,  *)
    var values: AsyncPublisher<AnyPublisher<Self.State, Never>> {
        publisher.values
    }
}

public extension StoreViewProvider {
    func value<T>(for keyPath: KeyPath<State, T>, shouldUpdateViewModelAccessToViewAccess: Bool = false, isSame: @escaping (T, T) -> Bool) -> T {
        let view = self.storeView
        
        var access = view.access
        if shouldUpdateViewModelAccessToViewAccess, access == .fromViewModel {
            access = .fromView
        }

        return view.context.value(for: view.path.appending(path: keyPath), access: access, isSame: isSame)
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
                        
        guard let initial = value(for: keyPath, shouldUpdateViewModelAccessToViewAccess: true, isSame: isSame) else {
            return nil
        }
        
        let view = storeView
        let unwrapPath = view.path(keyPath).appending(path: \T?[unwrapFallback: UnwrapFallback(initial)])
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

        let array = value(for: \.self, shouldUpdateViewModelAccessToViewAccess: true, isSame: isSame)
        return array.indices.map { index in
            let element = array[index]
            let cursor = Cursor<_, _, State.Index>(idPath: keyPath, id: element[keyPath: keyPath], index: index, fallback: element)
            let view = storeView
            let path = view.path.appending(path: \State[cursor: cursor])
            return IdentifiableStoreView(context: view.context, path: path, idPath: keyPath, access: view.access)
        }
    }
    
    subscript<C>(dynamicMember keyPath: WritableKeyPath<State, C>) -> [IdentifiableStoreView<Root, C.Element, C.Element.ID>] where C: MutableCollection, C: Equatable, C.Element: Identifiable, C.Index: Hashable {
        storeView(for: keyPath).id(\.id)
    }
}

public extension StoreViewProvider {
    /// Constructs a view model with a view into a store's state
    ///
    /// A view modal is required to be constructed from a view into a store's state for
    /// its `@ModelState` and other dependencies such as `@ModelEnvironment` to be
    /// set up correclty.
    ///
    ///     struct MyView: View {
    ///         @Model var model: MyModel
    ///
    ///         var body: some View {
    ///             SubView(model: $model.subState.viewModel(SubModel()))
    ///         }
    ///     }
    ///
    ///  To avoid having to repeat setup code for a view model for both view
    ///  and for testing the a TestStore, one can preferable add the view model
    ///  construction as a method to the parent model
    ///
    ///     extension MyModel {
    ///         var subModel: SubModel {
    ///             $state.subState.viewModel(SubModel())
    ///         }
    ///     }
    ///
    ///     struct MyView: View {
    ///         @Model var model: MyModel
    ///
    ///         var body: some View {
    ///             SubView(model: model.subModel)
    ///         }
    ///     }
    func viewModel<VM: ViewModel>(_ viewModel: @escaping @autoclosure () -> VM) -> VM where VM.State == State {
        let view = storeView
        let context = view.context.context(at: view.path)

        context.propertyIndex = 0
        return ContextBase.$current.withValue(context) {
             viewModel()
        }
    }
}

struct Cursor<Value, ID: Hashable, Index>: Hashable {
    var idPath: KeyPath<Value, ID>
    var id: ID
    var index: Index
    var fallback: Value
    
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.idPath == rhs.idPath && lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(idPath)
        hasher.combine(id)
    }
}

extension MutableCollection {
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
            
            self[index] = newValue
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
