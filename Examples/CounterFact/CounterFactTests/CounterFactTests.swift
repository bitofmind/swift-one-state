import XCTest
import OneState
import Dependencies
@testable import CounterFact

class CounterFactTests: XCTestCase {
    func testExample() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let store = TestStore<AppModel>(initialState: .init(counters: [])) {
            $0.factClient.fetch = { "\($0) is a good number." }
            $0.uuid = .constant(id)
        }

        @TestModel var appModel = store.model

        appModel.addButtonTapped()
        await $appModel.counters.assert([.init(counter: .init(), id: id)])

        @TestModel var counterRowModel = try XCTUnwrap(appModel.$counters.first)
        @TestModel var counterModel: CounterModel = counterRowModel.$counter

        counterModel.incrementTapped()
        await $counterModel.count.assert(1)

        counterModel.factButtonTapped()
        await $counterModel.receive(.onFact("1 is a good number."))
        await $appModel.factPrompt.assert(.init(count: 1, fact: "1 is a good number."))

        @TestModel var factPromptModel = try XCTUnwrap(appModel.$factPrompt)

        factPromptModel.send(.dismissButtonTapped)
        await $factPromptModel.receive(.dismissButtonTapped)
        await $appModel.factPrompt.assert(nil)

        counterRowModel.send(.removeButtonTapped)
        await $counterRowModel.receive(.removeButtonTapped)
        await $appModel.counters.assert([])
    }
}
