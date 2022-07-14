import Foundation

public struct TestFailure<State> {
    public var kind: Kind
    public var file: StaticString
    public var line: UInt

    public enum Kind {
        case assertStateMismatch(expected: State, actual: State)
        case receiveEventTimeout(event: Any)

        case stateNotExhausted(lastAsserted: State, actual: State)
        case eventNotExhausted(event: Any)
        case tasksAreStillRunning(modelName: String, taskCount: Int)
    }
}

public extension TestFailure {
    var message: String {
        switch kind {
        case let .assertStateMismatch(expected: expected, actual: actual):
            return
                   """
                    State change does not match expectation: …

                    Expected:
                    \(String(describing: expected).indent(by: 2))
                    Actual:
                    \(String(describing: actual).indent(by: 2))
                   """

        case let .receiveEventTimeout(event: event):
            return "Timeout while waiting to receive event: \(String(describing: event))"

        case let .stateNotExhausted(lastAsserted: lastAsserted, actual: actual):
            return
                   """
                    State not exhausted: …

                    Last Asserted:
                    \(String(describing: lastAsserted).indent(by: 2))
                    Actual:
                    \(String(describing: actual).indent(by: 2))
                   """

        case let .eventNotExhausted(event: event):
            return "Event not handled: \(String(describing: event))"

        case let .tasksAreStillRunning(modelName: modelName, taskCount: taskCount):
            return "Models of type `\(modelName)` have \(taskCount) active tasks still running"
        }
    }
}

extension String {
    func indent(by indent: Int) -> String {
        let indentation = String(repeating: " ", count: indent)
        return indentation + self.replacingOccurrences(of: "\n", with: "\n\(indentation)")
    }
}
