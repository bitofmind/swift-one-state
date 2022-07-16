import XCTest
import AsyncAlgorithms
@testable import OneState

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

    func testChildEvents() async throws {
        let store = TestStore<ParentModel>(initialState: .init(), onTestFailure: assertNoFailure)
        @TestModel var parent = store.model
        @TestModel var child = parent.$child

        await $child.count.assert(0)
        child.send(.count(3))

        await $parent.assert {
            $0.receivedEvents.append(.count(3))
            $0.receivedIds.append(child.id)
        }

        parent.setOptChild(id: 5)
        try await $parent.optChild.unwrap().assert(.init(id: 5))

        @TestModel var optChild = try XCTUnwrap(parent.$optChild)
        optChild.send(.count(7))

        await $parent.assert {
            $0.receivedEvents.append(.count(7))
            $0.receivedIds.append(optChild.id)
        }

        await store.assertExhausted(.state)
    }
}

private struct ChildModel: Model, Identifiable {
    struct State: Equatable, Identifiable {
        var id = 0
        var count = 0
    }

    enum Event: Equatable {
        case empty
        case count(Int)
    }

    @ModelState var state: State
}

private struct ParentModel: Model {
    struct State: Equatable {
        @StateModel<ChildModel> var child = .init(id: 1)
        @StateModel<ChildModel?> var optChild = nil
        @StateModel<[ChildModel]> var children = []

        var receivedEvents: [ChildModel.Event] = []
        var receivedIds: [Int] = []
    }

    @ModelState var state: State

    func onActivate() {
        forEach($state.$child.events()) { event in
            print("child", event, state.child.id)
            state.receivedEvents.append(event)
            state.receivedIds.append(state.child.id)
        }

        forEach($state.$optChild.events()) { event, child in
            print("opt child", event, child.id)
            state.receivedEvents.append(event)
            state.receivedIds.append(child.id)
        }
    }

    func setOptChild(id: Int) {
        state.optChild = .init(id: id)
    }
}
