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

    static var lock = Lock()
    static var _nextId = 0
    static var nextId: Int {
        lock {
            _nextId += 1
            return _nextId
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

final class Shared<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct AnyStateChange: @unchecked Sendable {
    var previous: AnyObject
    var current: AnyObject
    var isStateOverridden: Bool
    var isOverrideUpdate: Bool
    var callContexts: [CallContext] = []
}

class StoreAccess: @unchecked Sendable {
    func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) { }
    func didModify<State>(state: Shared<State>) { }
    func didSend(event: ContextBase.EventInfo) {}

    var allowAccessToBeOverridden: Bool { false }

    @TaskLocal static var current: Weak<StoreAccess>?
    @TaskLocal static var isInViewModelContext = false
}

struct Weak<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}

final class ThreadState: @unchecked Sendable {
    var stateModelCount = 0
    var pathFallbackCount = 0
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

public func reportPathDidFallback() {
    ThreadState.current.pathFallbackCount += 1
}
