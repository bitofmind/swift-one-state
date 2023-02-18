import Foundation

@propertyWrapper @dynamicMemberLookup
public final class TestModel<M: Model> where M.State: Equatable {
    public let wrappedValue: M

    public init(wrappedValue model: M) {
        wrappedValue = model
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
        await access.receive(event, context: wrappedValue.context, timeout: timeout, file: file, line: line)
    }

    func receive(_ event: some Equatable, timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async where M.Event: Equatable {
        await access.receive(event, context: wrappedValue.context, timeout: timeout, file: file, line: line)
    }
}

extension TestModel {
    var access: TestAccessBase {
        wrappedValue.storeView.access as! TestAccessBase
    }
}
