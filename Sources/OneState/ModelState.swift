import SwiftUI
import Combine

@propertyWrapper
@dynamicMemberLookup
public struct ModelState<State> {
    let context: Context<State>
    let isSame: (State, State) -> Bool
    
    public init(isSame: @escaping (State, State) -> Bool = { _, _ in false }) {
        guard let context = ContextBase.current as? Context<State> else {
            fatalError("ModelState can only be used from a ViewModel created via viewModel()")
        }
        self.context = context
        self.isSame = isSame
    }

    public init() where State: Equatable {
        self.init(isSame: ==)
    }

    public var wrappedValue: State {
        get {
            context[keyPath: \.self, access: access]
        }
        
        nonmutating set {
            guard !isSame(wrappedValue, newValue) else { return }
            context[keyPath: \.self, access: access] = newValue
        }
    }
    
    public var projectedValue: ModelState {
        self
    }
}

extension ModelState: StoreViewProvider {
    public var storeView: StoreView<State, State> {
        .init(context: context, path: \.self, access: .fromViewModel)
    }
}

public extension ModelState {
    var view: StateView<State, State> {
        .init(context: context, path: \.self)
    }

    func view<T>(_ path: WritableKeyPath<State, T>) -> StateView<State, T> {
        .init(context: context, path: path)
    }

    var binding: Binding<State> {
        binding(\.self)
    }

    func binding<T>(_ path: WritableKeyPath<State, T>) -> Binding<T> {
        .init {
            context[keyPath: path, access: access]
        } set: {
            context[keyPath: path, access: access] = $0
        }
    }

    func binding<T: Equatable>(_ path: WritableKeyPath<State, T>) -> Binding<T> {
        .init {
            context[keyPath: path, access: access]
        } set: {
            guard context[keyPath: path, access: access] != $0 else { return }
            context[keyPath: path, access: access] = $0
        }
    }
}

public extension ModelState {
    func transaction<T>(_ perform: @escaping (inout State) throws -> T) rethrows -> T {
        var result: T!
        _ = try context.modify(access: .fromViewModel) { state in
            result = try perform(&state)
        }
        return result
    }
    
    func transaction<T>(_ perform: @escaping (inout State) async throws -> T) async rethrows -> T {
        var state = context[keyPath: \.self, access: access]
        defer {
            context[keyPath: \.self, access: access] = state
        }
        return try await perform(&state)
    }
}

public extension ModelState {
    var isStateOverridden: Bool {
        context.isStateOverridden
    }
}

private extension ModelState {
    var access: StoreAccess {
        StoreAccess.viewModel ?? .fromView
    }
}
