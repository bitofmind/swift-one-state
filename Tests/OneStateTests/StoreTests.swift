import XCTest
@testable import OneState

private struct TestModel: Model {
    struct State {}
    @ModelState private var state: State
}

class StoreTests: XCTestCase {
    func testStoreRelease() throws {
        weak var weakStore: Store<TestModel>?
        do {
            let store = Store<TestModel>(initialState: .init())
            weakStore = store
        }
        XCTAssertNil(weakStore)
    }

    func testStoreContextRelease() throws {
        weak var weakStore: Store<TestModel>?
        var optContext: ChildContext<TestModel, TestModel>?
        do {
            let store = Store<TestModel>(initialState: .init())
            weakStore = store
            let context = store.context
            optContext = context
        }
        XCTAssertNotNil(weakStore)
        XCTAssertNotNil(optContext)
        weak var weakContext = optContext
        XCTAssertNotNil(weakContext)
        optContext?.removeRecursively()
        optContext = nil
        XCTAssertNil(weakContext)
        XCTAssertNil(weakStore)
    }
}
