import Foundation

class TestAccessBase: StoreAccess {
    func assert<Root, State>(view: StoreView<Root, State, Write>, modify: @escaping (inout State) -> Void, timeout: UInt64, file: StaticString, line: UInt) async {
        fatalError()
    }

    func receive<Event: Equatable>(_ event: Event, context: ContextBase, timeout: UInt64, file: StaticString, line: UInt) async {
        fatalError()
    }

    func unwrap<Root, T>(view: StoreView<Root, T?, Write>, timeout: UInt64, file: StaticString, line: UInt) async throws -> TestView<Root, T> {
        fatalError()
    }
}

final class TestAccess<State: Equatable>: TestAccessBase {
    var lock = Lock()
    private var _expectedState: State
    let onTestFailure: @Sendable (TestFailure<State>) -> Void
    var expectedState: State { lock { _expectedState } }

    final class Update<T> {
        private var lock = Lock()
        private var _values: [T] = []
        var values: [T] { lock { _values } }
    }

    let stateUpdate = Update<State>()
    let eventUpdate = Update<ContextBase.EventInfo>()

    init(state: State, onTestFailure: @escaping @Sendable (TestFailure<State>) -> Void) {
        self._expectedState = state
        self.onTestFailure = onTestFailure
        stateUpdate.receive(state)
    }

    var lastAssertedState: State { stateUpdate.values.first! }
    var lastReceivedState: State { stateUpdate.values.last! }

    func onTestFailure(_ kind: TestFailure<State>.Kind, file: StaticString, line: UInt) {
        onTestFailure(.init(kind: kind, file: file, line: line))
    }

    override func assert<Root, S>(view: StoreView<Root, S, Write>, modify: @escaping (inout S) -> Void, timeout: UInt64, file: StaticString, line: UInt) async {
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
            return await Task.yield()
        }

        if await stateUpdate.consume(upUntil: predicate, keepLast: true, timeout: timeout) {
            return await Task.yield()
        }

        onTestFailure(.assertStateMismatch(expected: expected, actual: lastReceivedState), file: file, line: line)
    }

    override func receive<Event: Equatable>(_ event: Event, context: ContextBase, timeout: UInt64, file: StaticString, line: UInt) async {
        @Sendable func predicate(value: ContextBase.EventInfo) -> Bool {
            guard let e = value.event as? Event, e == event, value.context === context else {
                return false
            }
            return true
        }

        if await !eventUpdate.consume(upUntil: predicate, timeout: timeout) {
            onTestFailure(.receiveEventTimeout(event: event), file: file, line: line)
        }

        await Task.yield()
    }

    override func unwrap<Root, T>(view: StoreView<Root, T?, Write>, timeout: UInt64, file: StaticString, line: UInt) async throws -> TestView<Root, T> {
        guard let unwrappedView: StoreView = view.storeView(for: \.self) else {
            throw UnwrapError()
        }

        lock {
            let shared = Shared(_expectedState)
            view.context[path: view.path, shared: shared] = unwrappedView.nonObservableState
            _expectedState = shared.value
        }

        @Sendable func predicate(_ value: State) -> Bool {
            let shared = Shared(value)
            return view.context[path: view.path, shared: shared] != nil
        }

        if predicate(lastAssertedState) {
            return TestView(storeView: unwrappedView)
        }

        if await stateUpdate.consume(upUntil: predicate, keepLast: true, timeout: timeout) {
            return TestView(storeView: unwrappedView)
        }

        onTestFailure(.unwrapFailed, file: file, line: line)
        throw UnwrapError()
    }

    override func didModify<S>(state: Shared<S>) {
        Swift.assert(State.self == S.self)
        stateUpdate.receiveSkipDuplicates(state.value as! State)
    }

    override func didSend(event: ContextBase.EventInfo) {
        eventUpdate.receive(event)
    }
}

struct UnwrapError: Error {}

extension TestAccess.Update {
    func receiveSkipDuplicates(_ value: T) where T: Equatable {
        lock {
            if let last = _values.last, value == last {
                return
            }
            _values.append(value)
        }
    }

    func receive(_ value: T) {
        lock {
            _values.append(value)
        }
    }

    func consumeAll() {
        lock {
            _values.removeAll()
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
