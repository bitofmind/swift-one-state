import Foundation
import XCTestDynamicOverlay
import CustomDump

public struct TestFailure<State> {
    public var kind: Kind
    public var file: StaticString
    public var line: UInt

    public enum Kind {
        case assertStateMismatch(expected: State, actual: State)
        case receiveEventTimeout(event: Any)
        case unwrapFailed

        case stateNotExhausted(lastAsserted: State, actual: State)
        case eventNotExhausted(event: Any)
        case tasksAreStillRunning(modelName: String, taskCount: Int)
    }
}

public extension TestFailure {
    var message: String {
        switch kind {
        case let .assertStateMismatch(expected: expected, actual: actual):
            let difference = diff(expected, actual, format: .proportional)
                .map { "\($0.indent(by: 4))\n\n(Expected: −, Actual: +)" }
            ??  """
                Expected:
                \(String(describing: expected).indent(by: 2))
                Actual:
                \(String(describing: actual).indent(by: 2))
                """

            return
                """
                State change does not match expectation: …
                \(difference)
                """

        case let .receiveEventTimeout(event: event):
            return "Timeout while waiting to receive event: \(String(describing: event))"

        case .unwrapFailed:
            return "Failed to unwrap value"

        case let .stateNotExhausted(lastAsserted: lastAsserted, actual: actual):
            let difference = diff(lastAsserted, actual, format: .proportional)
                .map { "\($0.indent(by: 4))\n\n(Last asserted: −, Actual: +)" }
            ??  """
                Last asserted:
                \(String(describing: lastAsserted).indent(by: 2))
                Actual:
                \(String(describing: actual).indent(by: 2))
                """

            return
                """
                State not exhausted: …
                \(difference)
                """

        case let .eventNotExhausted(event: event):
            return "Event not handled: \(String(describing: event))"

        case let .tasksAreStillRunning(modelName: modelName, taskCount: taskCount):
            return "Models of type `\(modelName)` have \(taskCount) active tasks still running"
        }
    }

    func assertNoFailure() {
        XCTFail(message, file: file, line: line)
    }
}

@Sendable public func assertNoFailure<State>(for failure: TestFailure<State>) {
    failure.assertNoFailure()
}

extension String {
    func indent(by indent: Int) -> String {
        let indentation = String(repeating: " ", count: indent)
        return indentation + self.replacingOccurrences(of: "\n", with: "\n\(indentation)")
    }
}
