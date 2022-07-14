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

struct EventModel: Model {
    struct State: Equatable {
        var count = 0
    }

    enum Event: Equatable {
        case empty
        case count(Int)
    }

    @ModelState var state: State

    func increment() {
        state.count += 1
        send(.count(state.count))
    }
}
