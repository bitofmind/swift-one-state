import SwiftUI

@dynamicMemberLookup
public struct StateView<State, Value> {
    let context: Context<State>
    public let path: WritableKeyPath<State, Value>
}

public extension StateView {
    var value: Value {
        get { self[dynamicMember: \.self] }
        nonmutating set { self[dynamicMember: \.self] = newValue }
    }

    var binding: Binding<State> {
        binding(\.self)
    }

    func binding<T>(_ path: WritableKeyPath<State, T>) -> Binding<T> {
        .init {
            context[keyPath: path, access: .fromViewModel]
        } set: {
            context[keyPath: path, access: .fromViewModel] = $0
        }
    }

    func binding<T: Equatable>(_ path: WritableKeyPath<State, T>) -> Binding<T> {
        .init {
            context[keyPath: path, access: .fromViewModel]
        } set: {
            guard context[keyPath: path, access: .fromViewModel] != $0 else { return }
            context[keyPath: path, access: .fromViewModel] = $0
        }
    }
}

public extension StateView {
    subscript<T>(dynamicMember path: WritableKeyPath<Value, T>) -> T {
        get {
            context[keyPath: self.path.appending(path: path), access: .fromViewModel]
        }
        nonmutating set {
            context[keyPath: self.path.appending(path: path), access: .fromViewModel] = newValue
        }
    }

    subscript<T: Equatable>(dynamicMember path: WritableKeyPath<Value, T>) -> T {
        get {
            context[keyPath: self.path.appending(path: path), access: .fromViewModel]
        }
        nonmutating set {
            guard self[dynamicMember: path] != newValue else { return }
            context[keyPath: self.path.appending(path: path), access: .fromViewModel] = newValue
        }
    }

    subscript<V, T>(dynamicMember keyPath: WritableKeyPath<V, T>) -> T? where V? == Value {
        get {
            value?[keyPath: keyPath]
        }
        nonmutating set {
            guard let val = newValue else { return }
            value?[keyPath: keyPath] = val
        }
    }

    subscript<V, T: Equatable>(dynamicMember path: WritableKeyPath<V, T>) -> T? where V? == Value {
        get {
            value?[keyPath: path]
        }
        nonmutating set {
            guard let val = newValue, val != value?[keyPath: path] else { return }
            value?[keyPath: path] = val
        }
    }
}

extension StateView: StoreViewProvider {
    public var storeView: StoreView<State, Value> {
        .init(context: context, path: path, access: .fromViewModel)
    }
}
