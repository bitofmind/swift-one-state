import SwiftUI
import Combine

// A view into a store's state
@dynamicMemberLookup
public struct StoreView<Root, State> {
    var context: Context<Root>
    var path: WritableKeyPath<Root, State>
    var access: StoreAccess?
}

extension StoreView: Identifiable where State: Identifiable {
    public var id: State.ID {
        context[path: path.appending(path: \.id), access: access]
    }
}

extension StoreView: Equatable where State: Equatable {
    public static func == (lhs: StoreView<Root, State>, rhs: StoreView<Root, State>) -> Bool {
        lhs.context[path: lhs.path, access: lhs.access] == rhs.context[path: rhs.path, access: lhs.access]
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
        let view = storeView
        return context.value(for: view.path(\.description), access: view.access)
    }
}

public extension LocalizedStringKey.StringInterpolation {
    // TODO: Add more support
    mutating func appendInterpolation<P>(_ string: P) where P: StoreViewProvider, P.State == String {
        appendInterpolation(string.value)
    }
}

@dynamicMemberLookup
public struct IdentifiableStoreView<Root, State, ID: Hashable>: Identifiable, StoreViewProvider {
    var context: Context<Root>
    var path: WritableKeyPath<Root, State>
    var idPath: KeyPath<State, ID>
    var access: StoreAccess?

    public var id: ID {
        context[path: path.appending(path: idPath), access: access]
    }
    
    public var storeView: StoreView<Root, State> { .init(context: context, path: path, access: access) }
}

extension StoreView: StoreViewProvider {
    public var storeView: Self { self }
}

