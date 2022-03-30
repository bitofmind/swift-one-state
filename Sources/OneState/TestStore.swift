import Foundation
import SwiftUI

public final class TestStore<State> {
    fileprivate var context: RootContext<State>
    fileprivate var environments: Environments = [:]
    
    private var onTestFailure: (TestFailure<State>) -> Void

    public init(state: State, onTestFailure: @escaping (TestFailure<State>) -> Void) {
        context = .init(state: state)
        context.isForTesting = true
        self.onTestFailure = onTestFailure
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
    func modelEnvironment<Value>(get: @escaping () -> Value, set: @escaping (Value) -> Void = { _ in }) -> Self {
        context.environments[ObjectIdentifier(Value.self)] = EnvironmentBinding(get: get, set: set)
        return self
    }

    func modelEnvironment<Value>(_ value: Value) -> Self {
        modelEnvironment(.constant(value))
    }
    
    func modelEnvironment<T>(_ value: Binding<T>) -> Self {
        modelEnvironment(get: { value.wrappedValue }, set: { value.wrappedValue = $0 })
    }
}

public extension TestStore where State: Equatable {
    func test(file: StaticString = #file, line: UInt = #line, _ block: @escaping (inout State) throws -> Void) rethrows {
        var state = context[keyPath: \.self, access: .test]
        try block(&state)

        guard state != context[keyPath: \.self, access: .test] else { return }
        
        onTestFailure(.init(
            expected: state,
            actual: context[keyPath: \.self, access: .test],
            file: file,
            line: line
        ))
    }

    func test(file: StaticString = #file, line: UInt = #line, _ block: @escaping (inout State) async throws -> Void) async rethrows {
        var state = context[keyPath: \.self, access: .test]
        try await block(&state)
            
        guard state != context[keyPath: \.self, access: .test] else { return }
        
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
