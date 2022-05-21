import SwiftUI
import Combine

@propertyWrapper
@dynamicMemberLookup
public struct ModelState<State> {
    let context: ContextBase
    weak var storeAccess: StoreAccess?
    let get: (StoreAccess?) -> State
    let set: (State, StoreAccess?) -> Void

    init(context: ContextBase, storeAccess: StoreAccess? = nil, get: @escaping (StoreAccess?) -> State, set: @escaping (State, StoreAccess?) -> Void) {
        self.context = context
        self.storeAccess = storeAccess
        self.get = get
        self.set = set
    }

    public init() {
        self.init(isSame: { _, _ in false })
    }

    public init() where State: Equatable {
        self.init(isSame: ==)
    }

    public var wrappedValue: State {
        get { get(nil) }
        nonmutating set { set(newValue, nil) }
    }
    
    public var projectedValue: Self {
        self
    }
}

public extension ModelState {
    subscript<T>(dynamicMember path: WritableKeyPath<State, T>) -> ModelState<T> {
        .init(
            context: context,
            storeAccess: storeAccess,
            get: { self.get($0)[keyPath: path] },
            set:  { newValue, access in
                var value = self.get(access)
                value[keyPath: path] = newValue
                self.set(value, access)
            }
        )
    }

    var isStateOverridden: Bool {
        context.isStateOverridden
    }
}

extension ModelState: Publisher where State: Equatable {
    public typealias Output = State
    public typealias Failure = Never

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == State, S.Failure == Never {
        context.stateDidUpdate.map { _ in
            get(nil)
        }
        .merge(with: Just(get(nil)))
        .removeDuplicates()
        .receive(subscriber: subscriber)
    }
}

public extension Binding {
    init(_ modelState: ModelState<Value>) {
        self.init(
            get: { modelState.get(modelState.storeAccess) },
            set: { modelState.set($0, modelState.storeAccess) }
        )
    }
}

extension ModelState {
    init(isSame: @escaping (State, State) -> Bool) {
        guard let context = ContextBase.current as? Context<State> else {
            fatalError("ModelState can only be used from a ViewModel that has been created with a view into a store")
        }
        self.context = context
        storeAccess = StoreAccess.current
        get = { context[path: \.self, access: $0] }
        set = { newValue, access in
            guard !isSame(context[path: \.self, access: access], newValue) else { return }
            context[path: \.self, access: access] = newValue
        }
    }
}

