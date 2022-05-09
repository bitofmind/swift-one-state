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

