import Foundation

struct CallContext: Identifiable, Sendable, Equatable {
    let id = Self.nextId
    let perform: @MainActor @Sendable (@MainActor @Sendable () -> Void) -> Void

    @MainActor
    func callAsFunction(_ action: @MainActor @Sendable () -> Void) {
        perform(action)
    }

    static func == (lhs: CallContext, rhs: CallContext) -> Bool {
        lhs.id == rhs.id
    }

    @TaskLocal static var currentContexts: [CallContext] = []

    static let _nextId = Protected(0)
    static var nextId: Int {
        _nextId.modify {
            $0 += 1
            return $0
        }
    }
}

struct WithCallContexts<Value> {
    let value: Value
    let callContexts: [CallContext]
}

extension WithCallContexts: Sendable where Value: Sendable {}

func withCallContext<Result>(body: () throws -> Result, perform: @escaping @MainActor @Sendable (@MainActor @Sendable () -> Void) -> Void) rethrows -> Result {
    try CallContext.$currentContexts.withValue(CallContext.currentContexts + [CallContext(perform: perform)]) {
        try body()
    }
}

func transaction<Result>(body: () throws -> Result) rethrows -> Result {
    try withCallContext(body: body) { action in
        action()
    }
}

@MainActor
func apply<C: Collection&Sendable>(callContexts: C, execute: @Sendable () -> Void) where C.Element == CallContext, C.SubSequence: Sendable {
    if callContexts.isEmpty {
        execute()
    } else {
        (callContexts.first!) {
            apply(callContexts: callContexts.dropFirst(), execute: execute)
        }
    }
}

struct StateUpdate: Sendable {
    var isStateOverridden: Bool
    var isOverrideUpdate: Bool
    var callContexts: [CallContext] = []
    var fromContext: ContextBase
}

protocol ComparableValue<Value>: Equatable {
    associatedtype Value
    init(value: Value)

    static var ignoreChildUpdates: Bool { get }
}

struct EquatableComparableValue<Value: Equatable>: ComparableValue {
    let value: Value

    static var ignoreChildUpdates: Bool { false }
}

struct StructureComparableValue<Value: StateContainer>: ComparableValue {
    let structureValue: Value.StructureValue

    init(value: Value) {
        structureValue = value.structureValue
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.structureValue == rhs.structureValue
    }

    static var ignoreChildUpdates: Bool { true }
}

struct IDCollectionComparableValue<Value: MutableCollection>: ComparableValue where Value.Element: Identifiable  {
    let structureValue: [Value.Element.ID]

    init(value: Value) {
        structureValue = value.map(\.id)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.structureValue == rhs.structureValue
    }

    static var ignoreChildUpdates: Bool { true }
}

class StoreAccess: @unchecked Sendable {
    func willAccess<StoreModel: Model, Comparable: ComparableValue>(store: Store<StoreModel>, from context: ContextBase, path: KeyPath<StoreModel.State, Comparable.Value>, comparable: Comparable.Type) { }
    func didModify<State>(state: State) { }
    func didSend(event: ContextBase.EventInfo) {}

    var allowAccessToBeOverridden: Bool { false }

    @TaskLocal static var current: Weak<StoreAccess>?
    @TaskLocal static var isInViewModelContext = false

    static func with<T>(_ access: (some StoreAccess)?, operation: () -> T) -> T {
        StoreAccess.$current.withValue(access.map(Weak.init), operation: operation)
    }
}

struct Weak<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}

final class ThreadState: @unchecked Sendable {
    var stateModelCount = 0
    var propertyIndex = 0
    var dependencyIndex = 0

    init() {}

    static var current: ThreadState {
        if let state = pthread_getspecific(threadStateKey) {
            return Unmanaged<ThreadState>.fromOpaque(state).takeUnretainedValue()
        }
        let state = ThreadState()
        pthread_setspecific(threadStateKey, Unmanaged.passRetained(state).toOpaque())
        return state
    }
}

private let threadStateKey: pthread_key_t = {
    var key: pthread_key_t = 0
    let cleanup: @convention(c) (UnsafeMutableRawPointer) -> Void = { state in
        Unmanaged<ThreadState>.fromOpaque(state).release()
    }
    pthread_key_create(&key, cleanup)
    return key
}()
