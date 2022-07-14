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
    func assert(_ value: State, file: StaticString = #file, line: UInt = #line) async {
        await assert(file: file, line: line) {
            $0 = value
        }
    }

    func assert(timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line, modify: @escaping (inout State) -> Void) async {
        await access.assert(view: testView.storeView, modify: modify, timeout: timeout, file: file, line: line)
    }

    subscript<T>(dynamicMember path: WritableKeyPath<State, T>) -> TestView<Root, T> {
        .init(storeView: testView.storeView.storeView(for: path))
    }

    func unwrap<T>(file: StaticString = #file, line: UInt = #line) -> TestView<Root, T> where State == T? {
        guard let view: StoreView = self.testView.storeView.storeView(for: \.self) else {
            fatalError("")
        }

        return TestView(storeView: view)
    }
}

@dynamicMemberLookup
public struct TestView<Root, State> {
    let storeView: StoreView<Root, State, Write>
}

extension TestView: TestViewProvider {
    public var testView: Self { self }
}

