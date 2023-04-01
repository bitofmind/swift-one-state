import Foundation

/// Declares a model's state
///
/// A model conforming to `Model` must declare its state  using `@ModelState` where
/// the type is matching its associated type `State`.
///
///     struct MyModel: Model {
///         @ModelState private var state: State
///     }
///
/// You then can create an instance by providing a store or a view into a store:
///
///     let model = MyModel($store)
///
///     let subModel = SubModel($store.sub)
///
/// But typically your are declaring your sub state using `@ModelState`:
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
            context.assertActive()
            yield context[path: \.self, access: storeAccess]
        }

        nonmutating _modify {
            context.assertActive()
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
    var isStateOverridden: Bool {
        context.isStateOverridden
    }
}

public extension ModelState {
    func transaction<T>(_ perform: (inout State) throws -> T) rethrows -> T {
        try perform(&wrappedValue)
    }
}
