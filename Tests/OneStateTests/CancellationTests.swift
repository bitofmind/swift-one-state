import XCTest
import AsyncAlgorithms
@testable import OneState

class CancelletionTests: XCTestCase {
    func testDestroyCancellation() {
        @Locked var count = 0

        do {
            let store = TestStore<CounterModel>(initialState: .init(), onTestFailure: assertNoFailure)

            store.model.onCancel {
                $count.wrappedValue += 5
            }
        }

        XCTAssertEqual(count, 5)
    }

    func testDoubleDestroyCancellation() {
        @Locked var count = 0

        do {
            let store = TestStore<CounterModel>(initialState: .init(), onTestFailure: assertNoFailure)
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
            let store = TestStore<TwoCountersModel>(initialState: .init(), onTestFailure: assertNoFailure)

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
            let store = TestStore<CounterModel>(initialState: .init(), onTestFailure: assertNoFailure)
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
            let store = TestStore<CounterModel>(initialState: .init(), onTestFailure: assertNoFailure)
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
}

enum CancelKey {}
enum CancelKey2 {}
