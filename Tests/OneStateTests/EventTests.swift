import XCTest
import AsyncAlgorithms
@testable import OneState

@Sendable func assertNoFailure<State>(failure: TestFailure<State>) {
    XCTFail("Expected no failures, but received: \(failure.message)", file: failure.file, line: failure.line)
}

final class EventTests: XCTestCase {
    func testModelEvents() async throws {
        let store = TestStore<EventModel>(initialState: .init(), onTestFailure: assertNoFailure)

        @TestModel var model = store.model

        await $model.count.assert(1)

        model.send(.empty)
        model.increment()
        model.increment()
        model.send(.empty)

        await $model.assert() {
            $0.count = 3
            $0.receivedEvents = [.empty, .count(2) , .count(3), .empty]
        }

        await store.assertExhausted(.state)
    }
}
