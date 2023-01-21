import XCTest
import AsyncAlgorithms
@testable import OneState

class CancelletionTests: XCTestCase {
    func testDestroyCancellation() {
        @Locked var count = 0

        do {
            let store = TestStore<CounterModel>(initialState: .init())

            store.model.onCancel {
                $count.wrappedValue += 5
            }
        }

        XCTAssertEqual(count, 5)
    }

    func testDoubleDestroyCancellation() {
        @Locked var count = 0

        do {
            let store = TestStore<CounterModel>(initialState: .init())
            @TestModel var model = store.model

            model.onCancel {
                $count.wrappedValue += 5
            }

            model.onCancel {
                $count.wrappedValue += 3
            }
        }

        XCTAssertEqual(count, 8)
    }

    func testKeyCancellation() {
        @Locked var count = 0

        do {
            let store = TestStore<TwoCountersModel>(initialState: .init())

            @TestModel var model = store.model
            @TestModel var counter1 = model.$counter1
            @TestModel var counter2 = model.$counter2

            counter1.onCancel {
                $count.wrappedValue += 5
            }
            .cancel(for: CancelKey.self)

            counter2.onCancel {
                $count.wrappedValue += 3
            }
            .cancel(for: CancelKey.self)

            XCTAssertEqual(count, 0)
            model.cancelAll(for: CancelKey.self)
            XCTAssertEqual(count, 8)
        }

        XCTAssertEqual(count, 8)
    }

    func testCancellationContext() {
        @Locked var count = 0

        do {
            let store = TestStore<CounterModel>(initialState: .init())
            @TestModel var model = store.model

            withCancellationContext(CancelKey.self) {
                model.onCancel {
                    $count.wrappedValue += 5
                }
            }
            
            model.cancelAll(for: CancelKey2.self)
            XCTAssertEqual(count, 0)
            model.cancelAll(for: CancelKey.self)
            XCTAssertEqual(count, 5)
        }

        XCTAssertEqual(count, 5)
    }

    func testCancelInFlight() async {
        @Locked var count = 0
        let channel = AsyncChannel<(Int)>()

        do {
            let store = TestStore<CounterModel>(initialState: .init())
            @TestModel var model = store.model

            async let v = Array(channel.prefix(1))

            model.task {
                await channel.send(1)
                try await withTaskCancellationHandler {
                    try await Task.sleep(nanoseconds: NSEC_PER_MSEC*10)
                } onCancel: {
                    $count.wrappedValue += 1
                }
                $count.wrappedValue += 5
            }
            .cancel(for: CancelKey.self, cancelInFlight: true)

            let _ = await v

            XCTAssertEqual(count, 0)

            model.onCancel {
                $count.wrappedValue += 3
            }
            .cancel(for: CancelKey.self, cancelInFlight: true)
            XCTAssertEqual(count, 1)
            
            model.cancelAll(for: CancelKey.self)
            XCTAssertEqual(count, 4)
        }

        XCTAssertEqual(count, 4)
    }

    func testCancelInFlightAlt() async throws {
        @Locked var count = 0

        do {
            let store = TestStore<CounterModel>(initialState: .init())
            @TestModel var model = store.model

            for _ in 1...5 {
                model.task {
                    try await withTaskCancellationHandler {
                        try await Task.sleep(nanoseconds: NSEC_PER_MSEC*100)
                    } onCancel: {
                        $count.wrappedValue += 1
                    }
                    $count.wrappedValue += 50
                }
                .cancelInFlight()

                try await Task.sleep(nanoseconds: NSEC_PER_MSEC*10)
            }

            XCTAssertEqual(count, 4)
        }

        XCTAssertEqual(count, 5)
    }

    func testForEachCancelPrevious() async throws {
        @Locked var count = 0
        let channel = AsyncChannel<Int>()
        let sync = AsyncChannel<()>()

        let store = TestStore<CounterModel>(initialState: .init())
        @TestModel var model = store.model

        model.forEach(channel, cancelPrevious: true) {
            $count.wrappedValue += $0
            await sync.send(())
        }
        .cancel(for: CancelKey.self)

        var it = sync.makeAsyncIterator()
        XCTAssertEqual(count, 0)
        await channel.send(1)
        await it.next()
        XCTAssertEqual(count, 1)

        await channel.send(10)
        await it.next()
        XCTAssertEqual(count, 11)

        await channel.send(100)
        await it.next()
        XCTAssertEqual(count, 111)

        model.cancelAll(for: CancelKey.self)
    }
}

enum CancelKey {}
enum CancelKey2 {}
