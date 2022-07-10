import Foundation

public final class TestStore<M: Model>: @unchecked Sendable {
    public typealias State = M.State

    let store: Store<M>
    let onTestFailure: (TestFailure<State>) -> Void

    public init(initialState: State, environments: [Any] = [], onTestFailure: @escaping @Sendable (TestFailure<State>) -> Void) {
        store = .init(initialState: initialState, environments: environments)
        store.context.isForTesting = true
        self.onTestFailure = onTestFailure
    }
}

public extension TestStore {
    convenience init<T>(initialState: T, environments: [Any] = [], onTestFailure: @escaping @Sendable (TestFailure<State>) -> Void) where M == EmptyModel<T> {
        self.init(initialState: initialState, environments: environments, onTestFailure: onTestFailure)
    }

    var model: M {
        M(self)
    }
}

public struct TestFailure<State> {
    public var expected: State
    public var actual: State
    public var file: StaticString
    public var line: UInt
}

extension TestStore: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        store.storeView
    }
}

public extension TestStore {
    func updateEnvironment<Value>(_ value: Value) {
        store.updateEnvironment(value)
    }
}

public extension TestStore where State: Equatable {
    func test(timeout: TimeInterval = 1.0, file: StaticString = #file, line: UInt = #line, _ block: @escaping (inout State) async throws -> Void) async rethrows {

        var state = store.state
        try await block(&state)

        let didPass = await withThrowingTaskGroup(of: Bool.self, returning: Bool.self) { [state] group in
            group.addTask {
                await self.values.first { $0 == state } != nil
            }

            group.addTask {
                try await Task.sleep(nanoseconds: NSEC_PER_MSEC * UInt64(timeout * 1_000))
                return false
            }

            do {
                let result = try await group.first { _ in true }!
                group.cancelAll()
                return result
            } catch {
                return false
            }
        }

        guard !didPass else { return }
        
        onTestFailure(.init(
            expected: state,
            actual: store.context[path: \.self, access: nil],
            file: file,
            line: line
        ))
    }
}

public extension TestFailure {
    var message: String {
        """
        State change does not match expectation: …
                      
        Expected:
        \(String(describing: expected).indent(by: 2))
        Actual:
        \(String(describing: actual).indent(by: 2))
       """
    }
}

extension String {
    func indent(by indent: Int) -> String {
        let indentation = String(repeating: " ", count: indent)
        return indentation + self.replacingOccurrences(of: "\n", with: "\n\(indentation)")
    }
}
