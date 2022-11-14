import Foundation

/// Declares a view models state
///
/// A model conforming to `Model` must declare its state  using `@ModelState` where
/// the type is matching its associatedtype `State`.
///
///     struct MyModel: Model {
///         @ModelState private var state: State
///     }
///
/// You then can create an instance by providing a store or a view into a store:
///
///     let model = MyModel($store)
///
///     let subModel = SubModel(model.sub)
///
/// Or by declaring you sub state using `@ModelState`:
///
///     let subModel = model.$sub
///
@propertyWrapper @dynamicMemberLookup
public struct ModelState<State> {
    let context: Context<State>
    weak var storeAccess: StoreAccess?

    public init() {
        guard let context = ContextBase.current as? Context<State> else {
            fatalError("ModelState can only be used from a Model with an injected store view.")
        }
        self.context = context
        storeAccess = StoreAccess.current?.value
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

extension ModelState: Sendable where State: Sendable {}

extension ModelState: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: storeAccess)
    }
}

public extension ModelState {
    func view<Value: Sendable&Equatable>(for path: WritableKeyPath<State, Value>) -> StateView<Value> {
        let view = self[dynamicMember: path]
        return .init(didUpdate: .init(view.values)) {
            view.nonObservableState
        } set: {
            view.context[path: view.path] = $0
        }
    }
}

public extension ModelState where State: Sendable&Equatable {
    var view: StateView<State> {
        return view(for: \.self)
    }
}

public extension ModelState {
    var isStateOverridden: Bool {
        context.isStateOverridden
    }
}
