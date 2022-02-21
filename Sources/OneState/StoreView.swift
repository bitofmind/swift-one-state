import SwiftUI
import Combine

@dynamicMemberLookup
public struct StoreView<Root, State> {
    var context: Context<Root>
    var path: WritableKeyPath<Root, State>
    var access: StoreAccess
}

extension StoreView: Identifiable where State: Identifiable {
    public var id: State.ID {
        context[keyPath: path.appending(path: \.id), access: access]
    }
}

extension StoreView: Equatable where State: Equatable {
    public static func == (lhs: StoreView<Root, State>, rhs: StoreView<Root, State>) -> Bool {
        lhs.context[keyPath: lhs.path, access: lhs.access] == rhs.context[keyPath: rhs.path, access: lhs.access]
    }
}

extension StoreView {
    func path<T>(_ keyPath: WritableKeyPath<State, T>) -> WritableKeyPath<Root, T>{
        storeView.path.appending(path: keyPath)
    }

    func path<T>(_ keyPath: KeyPath<State, T>) -> KeyPath<Root, T>{
        storeView.path.appending(path: keyPath)
    }
}

extension StoreView: CustomStringConvertible where State: CustomStringConvertible {
    public var description: String {
        context[keyPath: path.appending(path: \.description), access: .fromView]
    }
}

public extension LocalizedStringKey.StringInterpolation {
    // TODO: Add more support
    mutating func appendInterpolation<P>(_ string: P) where P: StoreViewProvider, P.State == String {
        let view = string.storeView
        return appendInterpolation(view.context[keyPath: view.path, access: view.access])
    }
}

@dynamicMemberLookup
public struct IdentifiableStoreView<Root, State, ID: Hashable>: Identifiable, StoreViewProvider {
    var context: Context<Root>
    var path: WritableKeyPath<Root, State>
    var idPath: KeyPath<State, ID>
    var access: StoreAccess

    public var id: ID {
        context[keyPath: path.appending(path: idPath), access: access]
    }
    
    public var storeView: StoreView<Root, State> { .init(context: context, path: path, access: access) }
}

extension StoreView: StoreViewProvider {
    public var storeView: Self { self }
}

