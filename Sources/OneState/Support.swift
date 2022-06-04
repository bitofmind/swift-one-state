import Foundation

struct CallContext: Identifiable {
    let id = UUID()
    let perform: (() -> Void) -> Void

    func callAsFunction(_ action: () -> Void) {
        perform(action)
    }

    @TaskLocal static var current: CallContext?

    static let empty = Self { $0() }
}

final class Shared<Value> {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct AnyStateChange {
    var previous: AnyObject
    var current: AnyObject
    var isStateOverridden: Bool
    var isOverrideUpdate: Bool
    var callContext: CallContext?
}

class StoreAccess {
    func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) { fatalError() }

    var allowAccessToBeOverridden: Bool { fatalError() }

    @TaskLocal static var current: StoreAccess?
    @TaskLocal static var isInViewModelContext = false
}

struct AnyCancellable: Cancellable {
    var onCancel: () -> Void

    func cancel() { onCancel() }
}

final class ThreadState {
    var stateModelCount = 0
    init() {}
}

var threadState: ThreadState {
    if let state = pthread_getspecific(threadStateKey) {
        return Unmanaged<ThreadState>.fromOpaque(state).takeUnretainedValue()
    }
    let state = ThreadState()
    pthread_setspecific(threadStateKey, Unmanaged.passRetained(state).toOpaque())
    return state
}

private var _threadStateKey: pthread_key_t = 0
private let threadStateKey: pthread_key_t = {
    let cleanup: @convention(c) (UnsafeMutableRawPointer) -> Void = { state in
             Unmanaged<ThreadState>.fromOpaque(state).release()
         }
    pthread_key_create(&_threadStateKey, cleanup)
    return _threadStateKey
 }()
