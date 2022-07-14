import Foundation

class TestAccessBase: StoreAccess {
    func assert<Root, State>(view: StoreView<Root, State, Write>, modify: @escaping (inout State) -> Void, timeout: UInt64, file: StaticString, line: UInt) async {
        fatalError()
    }

    func receive<Event: Equatable>(_ event: Event, context: ContextBase, timeout: UInt64, file: StaticString, line: UInt) async {
        fatalError()
    }
}

class TestAccess<State: Equatable>: TestAccessBase {
    var lock = Lock()
    private var _expectedState: State
    let onTestFailure: @Sendable (TestFailure<State>) async -> Void
    var expectedState: State { lock { _expectedState } }
    let initTask: Task<(), Never>

    final class Update<T> {
        private var lock = Lock()
        private var _values: [T] = []
        private let didUpdate = AsyncPassthroughSubject<T>()
        var values: [T] { lock { _values } }
    }

    let stateUpdate = Update<State>()
    let eventUpdate = Update<ContextBase.Event>()

    init(state: State, initTask: Task<(), Never>, onTestFailure: @escaping @Sendable (TestFailure<State>) async -> Void) {
        self._expectedState = state
        self.initTask = initTask
        self.onTestFailure = onTestFailure
    }

    var lastAssertedState: State { stateUpdate.values.first! }
    var lastReceivedState: State { stateUpdate.values.last! }

    func onTestFailure(_ kind: TestFailure<State>.Kind, file: StaticString, line: UInt) async {
        await onTestFailure(.init(kind: kind, file: file, line: line))
    }

    override func assert<Root, S>(view: StoreView<Root, S, Write>, modify: @escaping (inout S) -> Void, timeout: UInt64, file: StaticString, line: UInt) async {
        await initTask.value
        lock {
            let shared = Shared(_expectedState)
            modify(&view.context[path: view.path, shared: shared])
            _expectedState = shared.value
        }

        let expected = expectedState
        @Sendable func predicate(_ value: State) -> Bool {
            value == expected
        }

        if predicate(lastAssertedState) {
            return
        }

        if await stateUpdate.consume(upUntil: predicate, keepLast: true, timeout: timeout) {
            return
        }

        await onTestFailure(.assertStateMismatch(expected: expected, actual: lastReceivedState), file: file, line: line)
    }

    override func receive<Event: Equatable>(_ event: Event, context: ContextBase, timeout: UInt64, file: StaticString, line: UInt) async {
        @Sendable func predicate(value: ContextBase.Event) -> Bool {
            guard let e = value.event as? Event, e == event, value.context === context else {
                return false
            }
            return true
        }

        await initTask.value
        if await !eventUpdate.consume(upUntil: predicate, timeout: timeout) {
            await onTestFailure(.receiveEventTimeout(event: event), file: file, line: line)
        }
    }
}

extension TestAccess.Update {
    func receiveSkipDuplicates(_ value: T) where T: Equatable {
        lock {
            if let last = _values.last, value == last {
                return
            }
            _values.append(value)
            didUpdate.yield(value)
        }
    }

    func receive(_ value: T) {
        lock {
            _values.append(value)
            didUpdate.yield(value)
        }
    }

    func consume(upUntil predicate: @escaping @Sendable (T) -> Bool, keepLast: Bool = false, timeout: UInt64) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while start.distance(to: DispatchTime.now().uptimeNanoseconds) < timeout {
            let result: Bool = lock {
                if let index = _values.lastIndex(where: predicate) {
                    if keepLast {
                        _values.removeSubrange(..<index)
                    } else {
                        _values.removeSubrange(...index)
                    }

                    return true
                }
                return false
            }

            if result { return true }

            await Task.yield()
        }

        return false
    }
}
