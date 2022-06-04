import Foundation

@propertyWrapper
@dynamicMemberLookup
public struct ModelState<State> {
    let context: Context<State>
    weak var storeAccess: StoreAccess?

    public init() {
        guard let context = ContextBase.current as? Context<State> else {
            fatalError("ModelState can only be used from a ViewModel with an injected view.")
        }
        self.context = context
        storeAccess = StoreAccess.current
    }

    public var wrappedValue: State {
        _read {
            yield context[path: \.self, access: storeAccess]
        }

        nonmutating _modify {
            yield &context[path: \.self, access: storeAccess]
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
