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

            return previous != current ? current : nil
        }.merge(with: Just(value)).eraseToAnyPublisher()
    }
    
    @available(iOS 15, macOS 12,  *)
    var values: AsyncPublisher<AnyPublisher<Self.State, Never>> {
        publisher.values
    }
}

public extension StoreViewProvider {
    func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
        try SwiftUI.withAnimation(animation) {
            let result = try body()
            storeView.context.forceStateUpdate()
            return result
        }
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
    
    func storeView<T>(for keyPath: WritableKeyPath<State, T>) -> StoreView<Root, T> {
        let view = storeView
        return StoreView(context: view.context, path: view.path(keyPath), access: view.access)
    }
}

public extension StoreViewProvider {
    func setValue<T>(_ value: T, at keyPath: WritableKeyPath<State, Writable<T>>) {
        let view = storeView
        return view.context[path: view.path(keyPath), access: view.access] = .init(wrappedValue: value)
    }
}

public extension StoreViewProvider where State: Equatable {
    var value: State {
        value(for: \.self)
    }
}

public extension StoreViewProvider {
    subscript<T: Equatable>(dynamicMember keyPath: KeyPath<State, T>) -> T {
        value(for: keyPath)
    }

    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, T>) -> StoreView<Root, T> {
        storeView(for: keyPath)
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
                $0.context[path: $0.path, access: view.access]
            }, at: keyPath)
        }
    }
    
    subscript<T>(dynamicMember keyPath: WritableKeyPath<State, T?>) -> StoreView<Root, T>? {
        storeView(for: keyPath)
    }

    subscript<S, T>(dynamicMember keyPath: WritableKeyPath<S, T>) -> StoreView<Root, T>? where State == S? {
        storeView(for: \.self)?.storeView(for: keyPath)
    }

    subscript<S, T>(dynamicMember keyPath: WritableKeyPath<S, T?>) -> StoreView<Root, T>? where State == S? {
        storeView(for: \.self)?.storeView(for: keyPath)
    }
}

public extension StoreViewProvider {
    var nonObservableState: State {
        let view = self.storeView
        return view.context[path: view.path, access: view.access]
    }
}
