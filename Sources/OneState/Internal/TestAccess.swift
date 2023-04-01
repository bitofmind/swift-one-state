import Foundation
import CustomDump
import XCTestDynamicOverlay

class TestAccessBase: StoreAccess {
    func assert<Root, State: Equatable>(view: StoreView<Root, State, Write>, modify: @escaping (inout State) -> Void, timeout: UInt64, file: StaticString, line: UInt) async {
        fatalError()
    }

    func receive<Event: Equatable>(_ event: Event, context: ContextBase, timeout: UInt64, file: StaticString, line: UInt) async {
        fatalError()
    }
}

final class TestAccess<State: Equatable>: TestAccessBase {
    var lock = Lock()
    private var _expectedState: State
    var expectedState: State { lock { _expectedState } }
    var exhaustivity: Exhaustivity = .full
    var showSkippedAssertions = false

    final class Update<T> {
        private var lock = Lock()
        private var _values: [T] = []
        var values: [T] { lock { _values } }
    }

    let stateUpdate = Update<State>()
    let eventUpdate = Update<ContextBase.EventInfo>()

    init(state: State) {
        self._expectedState = state
        stateUpdate.receive(state)
    }

    var lastAssertedState: State { stateUpdate.values.first! }
    var lastReceivedState: State { stateUpdate.values.last! }

    override func assert<Root, S: Equatable>(view: StoreView<Root, S, Write>, modify: @escaping (inout S) -> Void, timeout: UInt64, file: StaticString, line: UInt) async {
        let storePath: WritableKeyPath<State, S> = view.context.storePath(for: view.path)!
        lock { modify(&_expectedState[keyPath: storePath]) }

        let isExhaustive = lock { self.exhaustivity.contains(.state) }
        let showSkippedAssertions = lock { self.showSkippedAssertions }
        let expected = expectedState
        @Sendable func predicate(_ value: State) -> Bool {
            if isExhaustive {
                return value == expected
            } else {
                let original = value[keyPath: storePath]
                var modified = original
                modify(&modified)
                return original == modified
            }
        }

        func diffMessage<T: Equatable>(expected: T, actual: T) -> String? {
            guard expected != actual else { return nil }
            return diff(expected, actual, format: .proportional)
                .map { "\($0.indent(by: 4))\n\n(Expected: −, Actual: +)" }
            ??  """
                Expected:
                \(String(describing: expected).indent(by: 2))
                Actual:
                \(String(describing: actual).indent(by: 2))
                """
        }

        func printNonExhaustiveDifference() {
            guard showSkippedAssertions, !isExhaustive,
                  let message = diffMessage(expected: expected, actual: lastReceivedState)
            else { return }

            fail(message, for: .state, file: file, line: line)
        }

        if predicate(lastAssertedState) {
            printNonExhaustiveDifference()
            return await Task.yield()
        }

        if await stateUpdate.consume(upUntil: predicate, keepLast: true, timeout: timeout) {
            printNonExhaustiveDifference()
            return await Task.yield()
        }

        let localDiff = diffMessage(expected: expected[keyPath: storePath], actual: lastReceivedState[keyPath: storePath])
        let totalDiff = diffMessage(expected: expected, actual: lastReceivedState)

        if isExhaustive  {
            if let localDiff {
                XCTFail(localDiff, file: file, line: line)
            } else if let totalDiff {
                XCTFail(totalDiff, file: file, line: line)
            }
        } else {
            var expected = lastReceivedState
            modify(&expected[keyPath: storePath])
            let noexhaustiveLocalDiff = diffMessage(expected: expected[keyPath: storePath], actual: lastReceivedState[keyPath: storePath])
            let noexhaustiveTotalDiff = diffMessage(expected: expected, actual: lastReceivedState)

            if let noexhaustiveLocalDiff {
                XCTFail(noexhaustiveLocalDiff, file: file, line: line)
            }

            if showSkippedAssertions {
                _XCTExpectFailure {
                    if let localDiff, localDiff != noexhaustiveLocalDiff {
                        XCTFail(localDiff, file: file, line: line)
                    } else if let totalDiff, totalDiff != noexhaustiveTotalDiff {
                        XCTFail(totalDiff, file: file, line: line)
                    }
                }
            }
        }
    }

    override func receive<Event: Equatable>(_ event: Event, context: ContextBase, timeout: UInt64, file: StaticString, line: UInt) async {
        @Sendable func predicate(value: ContextBase.EventInfo) -> Bool {
            guard let e = value.event as? Event, e == event, value.context === context else {
                return false
            }
            return true
        }

        if await !eventUpdate.consume(where: predicate, timeout: timeout) {
            XCTFail("Timeout while waiting to receive event: \(String(describing: event))", file: file, line: line)
        }

        await Task.yield()
    }

    override func didModify<S>(state: S) {
        Swift.assert(State.self == S.self)
        stateUpdate.receiveSkipDuplicates(state as! State)
    }

    override func didSend(event: ContextBase.EventInfo) {
        eventUpdate.receive(event)
    }

    func fail(_ message: String, for area: Exhaustivity, file: StaticString, line: UInt) {
        if lock({ exhaustivity.contains(area) }) {
            XCTFail(message, file: file, line: line)
        } else if lock({ showSkippedAssertions }) {
            _XCTExpectFailure {
                XCTFail(message, file: file, line: line)
            }
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

    func consume(where predicate: @escaping @Sendable (T) -> Bool, timeout: UInt64) async -> Bool {
        let start = DispatchTime.now().uptimeNanoseconds
        while start.distance(to: DispatchTime.now().uptimeNanoseconds) < timeout {
            let result: Bool = lock {
                if let index = _values.firstIndex(where: predicate) {
                    _values.remove(at: index)
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

extension String {
    func indent(by indent: Int) -> String {
        let indentation = String(repeating: " ", count: indent)
        return indentation + replacingOccurrences(of: "\n", with: "\n\(indentation)")
    }
}

private func _XCTExpectFailure(failingBlock: () -> Void) {
  #if DEBUG
    guard
      let XCTExpectedFailureOptions = NSClassFromString("XCTExpectedFailureOptions")
        as Any as? NSObjectProtocol,
      let options = XCTExpectedFailureOptions.perform(NSSelectorFromString("nonStrictOptions"))?.takeUnretainedValue()
    else { return }

    let XCTExpectFailureWithOptionsInBlock = unsafeBitCast(
      dlsym(dlopen(nil, RTLD_LAZY), "XCTExpectFailureWithOptionsInBlock"),
      to: (@convention(c) (String?, AnyObject, () -> Void) -> Void).self
    )

    XCTExpectFailureWithOptionsInBlock(nil, options, failingBlock)
  #endif
}
