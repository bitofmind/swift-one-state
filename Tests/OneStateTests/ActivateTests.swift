import XCTest
import AsyncAlgorithms
@testable import OneState

class ActivateTests: XCTestCase {
    func testActivation() async throws {
        let store = TestStore<EventModel>(initialState: .init(), onTestFailure: assertNoFailure)

        XCTAssertFalse(store.model.isActive)

        let cancelable = store.model.activate()
        XCTAssertTrue(store.model.isActive)

        cancelable.cancel()
        XCTAssertFalse(store.model.isActive)

        do {
            @TestModel var outer = store.model

            XCTAssertTrue(outer.isActive)

            await $outer.count.assert(2)

            do {
                @TestModel var inner = store.model
                XCTAssertTrue(inner.isActive)

            }

            XCTAssertTrue(outer.isActive)
        }

        XCTAssertFalse(store.model.isActive)
    }

    func testChildActivation() async throws {
        let store = TestStore<ParentModel>(initialState: .init(), onTestFailure: assertNoFailure)
        XCTAssertFalse(store.model.isActive)

        do {
            @TestModel var parent = store.model
            XCTAssertTrue(parent.isActive)

            await $parent.child.id.assert(1)

            XCTAssertFalse(parent.$child.isActive)
            let c1 = parent.activate(parent.$child)

            await $parent.assert {
                $0.events.append(.didActivate(1))
            }

            XCTAssertTrue(parent.$child.isActive)
            c1.cancel()
            XCTAssertFalse(parent.$child.isActive)

            await $parent.assert {
                $0.events.append(.didDeactivate(1))
            }

            parent.setOptChild(id: 5)
            let optChild = try XCTUnwrap(parent.$optChild)
            XCTAssertFalse(optChild.isActive)

            await $parent.assert {
                $0.optChild = .init(id: 5)
                $0.events.append(.didActivate(5))
            }

            parent.clearOptChild()
            await $parent.optChild.assert(nil) // deactivate will never be recieved as reciever does no longer exists

            parent.addChild(id: 7)

            let child = try XCTUnwrap(parent.$children.first)
            XCTAssertFalse(child.isActive)

            await $parent.assert {
                $0.children.append(.init(id: 7))
                $0.events.append(.didActivate(7))
            }

            parent.clearChildren()
            await $parent.children.assert([])
        }

        store.exhaustEvents()
    }
}


private struct ChildModel: Model, Identifiable {
    struct State: Equatable, Identifiable {
        var id = 0
    }

    enum Event: Equatable {
        case didActivate(Int)
        case didDeactivate(Int)
    }

    @ModelState var state: State

    func onActivate() {
        send(.didActivate(state.id))
        onDeactivate {
            send(.didDeactivate(state.id))
        }
    }
}

private struct ParentModel: Model {
    struct State: Equatable {
        @StateModel<ChildModel> var child = .init(id: 1)
        @StateModel<ChildModel?> var optChild = nil
        @StateModel<[ChildModel]> var children = []

        var events: [ChildModel.Event] = []
    }

    @ModelState var state: State

    func onActivate() {
        forEach(self.$child.events()) { event in
            state.events.append(event)
        }

        forEach($state.$optChild.events()) { event, child in
            state.events.append(event)
        }

        forEach($state.$children.events()) { event, child in
            state.events.append(event)
        }

        activate($state.$optChild)
        activate($state.$children)
    }

    func setOptChild(id: Int) {
        state.optChild = .init(id: id)
    }

    func clearOptChild() {
        state.optChild = nil
    }

    func addChild(id: Int) {
        state.children.append(.init(id: id))
    }

    func clearChildren() {
        state.children.removeAll()
    }
}
