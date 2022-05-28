import Foundation

@propertyWrapper
@dynamicMemberLookup
public struct ModelState<State> {
    let context: Context<State>
    weak var storeAccess: StoreAccess?
    let isSame: (State, State) -> Bool

    public init(isSame: @escaping (State, State) -> Bool = { _, _ in false }) {
        guard let context = ContextBase.current as? Context<State> else {
            fatalError("ModelState can only be used from a ViewModel created via viewModel()")
        }
        self.context = context
        storeAccess = StoreAccess.current
        self.isSame = isSame
    }

    public init() where State: Equatable {
        self.init(isSame: ==)
    }

    public var wrappedValue: State {
        get {
            context[path: \.self, access: storeAccess]
        }

        nonmutating set {
            guard !isSame(wrappedValue, newValue) else { return }
            context[path: \.self, access: storeAccess] = newValue
        }
    }

    public var projectedValue: ModelState {
        self
    }
}

extension ModelState: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: storeAccess)
    }
}

public extension ModelState where State: Equatable {
    var stateView: StateView<State> {
        .init(didUpdate: values) {
            wrappedValue
        } set: {
            wrappedValue = $0
        }
    }
}

public extension ModelState {
    var isStateOverridden: Bool {
        context.isStateOverridden
    }
}

#if canImport(SwiftUI)
import SwiftUI

public extension Binding where Value: Equatable {
    init(_ modelState: ModelState<Value>) {
        self.init(
            get: { modelState.context.value(for: \.self, access: modelState.storeAccess) },
            set: { modelState.wrappedValue = $0 }
        )
    }
}

#endif
