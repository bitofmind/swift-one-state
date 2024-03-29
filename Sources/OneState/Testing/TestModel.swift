import Foundation
import XCTestDynamicOverlay

@propertyWrapper @dynamicMemberLookup
public final class TestModel<M: Model> where M.State: Equatable {
    private let _wrappedValue: M

    public init(wrappedValue model: M) {
        _wrappedValue = model
    }
    
    public var wrappedValue: M {
        _wrappedValue.context.assertActive(refreshContainers: true)
        return _wrappedValue
    }
    
    public var projectedValue: TestModel<M> {
        self
    }
}

extension TestModel: StoreViewProvider {
    public var storeView: StoreView<M.State, M.State, Write> {
        wrappedValue.storeView
    }
}

extension TestModel: TestViewProvider {
    public var testView: TestView<M.State, M.State> {
        TestView(storeView: storeView)
    }
}

public extension TestModel {
    func receive(_ event: M.Event, timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async where M.Event: Equatable {
        await access.receive(event, context: _wrappedValue.context, timeout: timeout, file: file, line: line)
    }

    func receive(_ event: some Equatable, timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async where M.Event: Equatable {
        await access.receive(event, context: _wrappedValue.context, timeout: timeout, file: file, line: line)
    }
}

extension TestModel {
    var access: TestAccessBase {
        wrappedValue.storeView.access as! TestAccessBase
    }
}
