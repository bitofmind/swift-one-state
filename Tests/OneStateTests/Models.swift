import OneState

struct CounterModel: Model {
    struct State: Equatable {
        var count = 0
    }

    @ModelState private var state: State

    func increment() {
        state.count += 1
    }
}

struct TwoCountersModel: Model {
    struct State: Equatable {
        @StateModel<CounterModel> var counter1 = .init(count: 1)
        @StateModel<CounterModel> var counter2 = .init(count: 2)
    }

    @ModelState private var state: State
}

struct EventModel: Model, Identifiable {
    struct State: Equatable, Identifiable {
        var id = 0
        @Writable var count = 0
        var receivedEvents: [EventModel.Event] = []
    }

    enum Event: Equatable {
        case empty
        case count(Int)
    }

    @ModelState private var state: State

    func onActivate() {
        forEach(events()) {
            state.receivedEvents.append($0)
        }

        state.count += 3
    }

    func increment() {
        state.count += 1
        send(.count(state.count))
    }
}


