import Foundation
import OneState
import AsyncAlgorithms
import CustomDump

public extension TimeTraveler {
    static func local<Models: ModelContainer>(for store: Store<Models>, reducer: StateHistoryReducer<Models.Container> = .timeDelta()) -> Self {
        let localOverride = LocalOverride(for: store, reducer: reducer)
        Task {
            await localOverride.startListening()
        }
        
        return Self(
            stateStream: { localOverride.stateStream },
            setOverride: { index in
                Task {
                    await localOverride.setOverride(index)
                }
            },
            printDiff: { index in
                Task {
                    await localOverride.printDiff(for: index)
                }
            }
        )
    }
}

actor LocalOverride<Models: ModelContainer> {
    typealias State = Models.Container
    typealias Record = StateRecord<State>
    
    let store: Store<Models>
    let stateChannel = AsyncChannel<OverrideState?>()
    let reducer: StateHistoryReducer<State>
    var states: [Record] = []
    var overrideStates: [Record] = []
    var overrideIndex: Int? = nil
    var task: Task<(), Never>? = nil
    
    init(for store: Store<Models>, reducer: StateHistoryReducer<State>) {
        self.store = store
        self.reducer = reducer
    }
    
    deinit {
        task?.cancel()
    }
    
    func startListening() {
        add(store.state)
        task = Task {
            for await _ in store.stateDidUpdate {
                add(store.state)
            }
        }
    }
    
    func add(_ state: State) {
        let record = StateRecord(state: state)
        states.append(record)
        reducer(&states)
    }
    
    func setOverride(_ index: Int?) async -> Void {
        if let index {
            if overrideIndex == nil {
                overrideStates = states
            }
            let count = overrideStates.count
            let overrideIndex = max(0, min(count - 1, index))
            self.overrideIndex = overrideIndex
            
            store.stateOverride = overrideStates[overrideIndex].state
            
            await stateChannel.send(.init(index: overrideIndex, count: count))
        } else {
            overrideIndex = nil
            overrideStates = []
            store.stateOverride = nil

            await stateChannel.send(nil)
        }
    }
    
    func printDiff(for index: Int) {
        let index = max(0, min(overrideStates.count - 1, index))
        guard index > 0, let diff = diff(overrideStates[index - 1].state, overrideStates[index].state) else { return }
        
        print("Traveler state update:\n" + diff)
    }
    
    var overrideState: OverrideState? {
        overrideIndex.map {
            .init(index: $0, count: overrideStates.count)
        }
    }
    
    nonisolated var stateStream: AsyncStream<OverrideState?> {
        let state = AsyncStream<()> { c in
            c.yield(())
            c.finish()
        }.map {
            await self.overrideState
        }
        return AsyncStream(chain(state, stateChannel))
    }
}
