import OneState

struct CounterModel: Model {
    struct State: Equatable {
        var count = 0
    }

    @ModelState var state: State

    func increment() {
        state.count += 1
    }
}

struct TwoCountersModel: Model {
    struct State: Equatable {
        @StateModel<CounterModel> var counter1 = .init(count: 1)
        @StateModel<CounterModel> var counter2 = .init(count: 2)
    }

    @ModelState var state: State
}

struct EventModel: Model, Identifiable {
    struct State: Equatable, Identifiable {
        var id = 0
        var count = 0
        var receivedEvents: [EventModel.Event] = []
    }

    enum Event: Equatable {
        case empty
        case count(Int)
    }

    @ModelState var state: State

    func onActivate() {
        forEach(events()) {
            state.receivedEvents.append($0)
        }

        state.count += 1
    }

    func increment() {
        state.count += 1
        send(.count(state.count))
    }
}


