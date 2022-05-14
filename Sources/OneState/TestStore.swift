import Foundation
import Combine

public final class TestStore<Model: ViewModel> {
    public typealias State = Model.State

    var context: RootContext<State>
    var environments: Environments = [:]
    var onTestFailure: (TestFailure<State>) -> Void

    public init(state: State, onTestFailure: @escaping (TestFailure<State>) -> Void) {
        context = .init(state: state)
        context.isForTesting = true
        self.onTestFailure = onTestFailure
    }
}

public extension TestStore {
    convenience init<T>(state: T, onTestFailure: @escaping (TestFailure<State>) -> Void) where Model == EmptyModel<T> {
        self.init(state: state, onTestFailure: onTestFailure)
    }

    var model: Model {
        Model(self)
    }
}

public struct TestFailure<State> {
    public var expected: State
    public var actual: State
    public var file: StaticString
    public var line: UInt
}

extension TestStore: StoreViewProvider {
    public var storeView: StoreView<State, State> {
        .init(context: context, path: \.self, access: .test)
    }
}

public extension TestStore {
    func modelEnvironment<Value>(_ value: Value) -> Self {
        context.localEnvironments[ObjectIdentifier(Value.self)] = value
        return self
    }
}

public extension TestStore where State: Equatable {
    func test(timeout: TimeInterval = 1.0, file: StaticString = #file, line: UInt = #line, _ block: @escaping (inout State) async throws -> Void) async rethrows {

        var state = context[keyPath: \.self, access: .test]
        try await block(&state)

        let didPass = await withThrowingTaskGroup(of: Bool.self, returning: Bool.self) { [state] group in
            group.addTask {
                await AsyncStream<Bool> { cont in
                    let cancellable = self.context.stateDidUpdate
                        .map { _ in }
                        .merge(with: Just(()))
                        .filter { self.context[keyPath: \.self, access: .test] == state }
                        .sink {
                            cont.yield(true)
                        }

                    cont.onTermination = { _ in
                        cont.yield(false)
                        cancellable.cancel()
                    }
                }.first { _ in true }!
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
            actual: context[keyPath: \.self, access: .test],
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
