import XCTest
@testable import OneState

final class EventTests: XCTestCase {
    func testModelEvent() async throws {
        let store = Store<EventModel>(initialState: .init())
        let model = store.model

        async let events = Array(model.events().prefix(4))

        try await Task.sleep(nanoseconds: NSEC_PER_MSEC*20)

        model.send(.empty)
        model.increment()
        model.increment()
        model.send(.empty)

        let received = await events
        XCTAssertEqual(received, [.empty, .count(1) , .count(2), .empty])
    }

    func testModelEventWithContext() async throws {
        func with<Result>(count: Int, body: @escaping () throws -> Result) rethrows -> Result {
            try withCallContext(body: body) { body in
                Int.$current.withValue(count) {
                    body()
                }
            }
        }

        let store = Store<EventModel>(initialState: .init())
        let model = store.model

        let counts = Locked<[Int]>([])
        let currents = Locked<[Int]>([])

        model.forEach(model.events()) { event in
            switch event {
            case .empty:
                model.state.count += 1
            case let .count(val):
                model.state.count = val
            }
            try await Task.sleep(nanoseconds: NSEC_PER_MSEC*10)
        }

        Task { @MainActor in
            for await update in store.stateUpdates {
                await OneState.perform(with: update.stateChange.callContext) {
                    counts.value.append(update.current.count)
                    currents.value.append(Int.current)
                }
            }
        }

        try await Task.sleep(nanoseconds: NSEC_PER_MSEC*20)

        with(count: 5) {
            model.send(.empty)
        }

        with(count: 7) {
            model.send(.count(4))
            model.send(.count(2))
        }

        model.send(.empty)

        try await Task.sleep(nanoseconds: NSEC_PER_MSEC*120)

        XCTAssertEqual(counts.value, [1, 4, 2, 3])
        XCTAssertEqual(currents.value, [5, 7, 7, 0])
    }
}

extension Int {
    @TaskLocal static var current = 0
}
