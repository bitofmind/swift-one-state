import XCTest
import AsyncAlgorithms
@testable import OneState

final class EventTests: XCTestCase {
    func testModelEvents() async throws {
        let store = TestStore<EventModel>(initialState: .init())
        @TestModel var model = store.model

        await $model.count.assert(3)

        try await Task.sleep(nanoseconds: NSEC_PER_MSEC*1)

        model.send(.empty)
        model.increment()
        model.increment()
        model.send(.empty)

        await $model.assert() {
            $0.count = 3 + 1 + 1
            $0.receivedEvents = [.empty, .count(4) , .count(5), .empty]
        }

        await $model.receive(.empty)
        await $model.receive(.count(4))
        await $model.receive(.count(5))
        await $model.receive(.empty)
    }

    func testChildEvents() async throws {
        let store = TestStore<ParentModel>(initialState: .init())
        @TestModel var parent = store.model
        @TestModel var child = parent.$child

        await $child.id.assert(1)
        child.send(.count(3))

        await $parent.assert {
            $0.receivedEvents.append(.count(3))
            $0.receivedIds.append(10 + child.id)
        }

        @TestModel var childAlt = parent.$childAlt
        childAlt.send(.count(9))

        await $parent.assert {
            $0.receivedEvents.append(.count(9))
            $0.receivedIds.append(30 + childAlt.id)
        }

        parent.setOptChild(id: 5)
        await $parent.optChild.assert(.init(id: 5))

        @TestModel var optChild = try XCTUnwrap(parent.$optChild)
        optChild.send(.count(7))

        await $parent.assert {
            $0.receivedEvents.append(.count(7))
            $0.receivedIds.append(20 + optChild.id)
        }

        parent.addChild(id: 8)
        parent.addChild(id: 3)

        await $parent.children.assert([.init(id: 8), .init(id: 3)])
        @TestModel var child1 = parent.$children[0]
        @TestModel var child2 = parent.$children[1]

        child2.send(.count(1))

        await $parent.assert {
            $0.receivedEvents.append(.count(1))
            $0.receivedIds.append(40 + child2.id)
        }

        child1.send(.empty)
        child2.send(.count(2))

        await $parent.assert {
            $0.receivedEvents += [.empty, .count(2)]
            $0.receivedIds +=  [40 + child1.id, 40 + child2.id]
        }

        await $child.receive(.count(3))
        await $childAlt.receive(.count(9))
        await $optChild.receive(.count(7))
        await $child2.receive(.count(1))
        await $child1.receive(.empty)
        await $child2.receive(.count(2))
    }
}

private struct ChildModel: Model, Identifiable {
    struct State: Equatable, Identifiable {
        var id = 0
    }

    enum Event: Equatable {
        case empty
        case count(Int)
    }

    @ModelState private var state: State
}

private struct ParentModel: Model {
    struct State: Equatable {
        @StateModel<ChildModel> var child = .init(id: 1)
        @StateModel<ChildModel> var childAlt = .init(id: 9)
        @StateModel<ChildModel?> var optChild = nil
        @StateModel<[ChildModel]> var children = []

        var receivedEvents: [ChildModel.Event] = []
        var receivedIds: [Int] = []
    }

    @ModelState private var state: State

    func onActivate() {
        forEach(events(from: \.$child)) { event in
            state.receivedEvents.append(event)
            state.receivedIds.append(10 + state.child.id)
        }

        forEach(events(from: \.$childAlt)) { event in
            state.receivedEvents.append(event)
            state.receivedIds.append(30 + state.childAlt.id)
        }

        forEach(events(from: \.$optChild)) { event, child in
            state.receivedEvents.append(event)
            state.receivedIds.append(20 + child.id)
        }

        forEach(events(from: \.$children)) { event, child in
            state.receivedEvents.append(event)
            state.receivedIds.append(40 + child.id)
        }
    }

    func setOptChild(id: Int) {
        state.optChild = .init(id: id)
    }

    func addChild(id: Int) {
        state.children.append(.init(id: id))
    }
}
