import XCTest
import AsyncAlgorithms
@testable import OneState

final class CallContextTests: XCTestCase {
    func testModelEventWithContext() async throws {
        let store = TestStore<EventModel>(initialState: .init(), onTestFailure: assertNoFailure)

        let countsChannel = AsyncChannel<Int>()
        async let counts = Array(countsChannel.prefix(4))

        let currentAChannel = AsyncChannel<Int>()
        async let currentA = Array(currentAChannel.prefix(4))

        let currentBChannel = AsyncChannel<Int>()
        async let currentB = Array(currentBChannel.prefix(4))

        let syncChannel = AsyncChannel<()>()
        Task {
            await syncChannel.first { _ in true }
            for await update in store.stateUpdates.removeDuplicates() {
                let count = update.current.count
                guard count > 0 else { continue }

                let currentA = Locked(-1)
                let currentB = Locked(-1)
                await apply(callContexts: update.stateChange.callContexts) {
                    currentA.value = .currentA
                    currentB.value = .currentB
                }
                await currentAChannel.send(currentA.value)
                await currentBChannel.send(currentB.value)
                await countsChannel.send(count)
            }
        }

        await syncChannel.send(())

        @TestModel var model = store.model

        model.forEach(model.events()) { event in
            switch event {
            case .empty:
                model.state.count += 1
            case let .count(val):
                model.state.count = val
            }
        }

        await $model.count.assert(1)

        withA(count: 5) {
            withB(count: 2) {
                model.send(.empty)
            }
        }

        await $model.receive(.empty)
        await $model.assert {
            $0.count = 2
            $0.receivedEvents += [.empty]
        }

        withA(count: 7) {
            withB(count: 6) {
                withA(count: 4) {
                    model.send(.count(4))
                }
            }
        }
        await $model.receive(.count(4))

        await $model.assert {
            $0.count = 4
            $0.receivedEvents += [.count(4)]
        }

        withB(count: 9) {
            model.send(.empty)
        }
        await $model.receive(.empty)

        await $model.assert {
            $0.count += 1
            $0.receivedEvents += [.empty]
        }

        await store.assertExhausted([.state, .events])

        let finalCounts = await counts
        let finalCurrentA = await currentA
        let finalCurrentB = await currentB
        XCTAssertEqual(finalCounts, [1, 2, 4, 5])
        XCTAssertEqual(finalCurrentA, [0, 5, 4, 0])
        XCTAssertEqual(finalCurrentB, [0, 2, 6, 9])
    }
}

extension Int {
    @TaskLocal static var currentA = 0
    @TaskLocal static var currentB = 0
}

func withA<Result>(count: Int, body: @escaping () throws -> Result) rethrows -> Result {
    try withCallContext(body: body) { body in
        Int.$currentA.withValue(count) {
            body()
        }
    }
}

func withB<Result>(count: Int, body: @escaping () throws -> Result) rethrows -> Result {
    try withCallContext(body: body) { body in
        Int.$currentB.withValue(count) {
            body()
        }
    }
}
