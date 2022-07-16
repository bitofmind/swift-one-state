import Foundation

public protocol TestViewProvider {
    associatedtype Root
    associatedtype State

    var testView: TestView<Root, State> { get }
}

extension TestViewProvider {
    var access: TestAccessBase { testView.storeView.access as! TestAccessBase }
}

public extension TestViewProvider {
    func assert(_ value: State, timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async {
        await assert(timeoutNanoseconds: timeout, file: file, line: line) {
            $0 = value
        }
    }

    func assert(timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line, modify: @escaping (inout State) -> Void) async {
        await access.assert(view: testView.storeView, modify: modify, timeout: timeout, file: file, line: line)
    }

    subscript<T>(dynamicMember path: WritableKeyPath<State, T>) -> TestView<Root, T> {
        .init(storeView: testView.storeView.storeView(for: path))
    }

    func unwrap<T>(timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async throws -> TestView<Root, T> where State == T? {
        try await access.unwrap(view: testView.storeView, timeout: timeout, file: file, line: line)
    }
}

@dynamicMemberLookup
public struct TestView<Root, State> {
    let storeView: StoreView<Root, State, Write>
}

extension TestView: TestViewProvider {
    public var testView: Self { self }
}

