import Foundation

struct CallContext: Identifiable, Sendable {
    let id = UUID()
    let perform: @Sendable (@Sendable () -> Void) async -> Void

    func callAsFunction(_ action: @Sendable () -> Void) async {
        await perform(action)
    }

    @TaskLocal static var current: CallContext?
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
    var callContext: CallContext?
}

class StoreAccess: @unchecked Sendable {
    func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) { fatalError() }

    var allowAccessToBeOverridden: Bool { fatalError() }

    @TaskLocal static var current: Weak<StoreAccess>?
    @TaskLocal static var isInViewModelContext = false
}

struct Weak<T: AnyObject>: @unchecked Sendable {
    weak var value: T?
}

struct AnyCancellable: Cancellable {
    var onCancel: () -> Void

    func cancel() { onCancel() }
}

final class ThreadState: @unchecked Sendable {
    var stateModelCount = 0
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
