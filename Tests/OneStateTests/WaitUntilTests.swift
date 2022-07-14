import XCTest
@testable import OneState

final class WaitUntilTests: XCTestCase {
    func testCurrent() async throws {
        let store = Store<CounterModel>(initialState: .init())
        let counter = store.model

        try await counter.waitUntil(counter.count == 0)
    }

    func testIncrement() async throws {
        let store = Store<CounterModel>(initialState: .init())
        let counter = store.model

        let task = Task {
            try await counter.waitUntil(counter.count == 1)
        }
        counter.increment()

        try await task.value
    }

    func testIncrementMany() async throws {
        let store = Store<CounterModel>(initialState: .init())
        let counter = store.model

        let task = Task {
            try await counter.waitUntil(counter.count >= 3)
        }

        for _ in 1...5 {
            counter.increment()
        }

        try await task.value
    }
}
