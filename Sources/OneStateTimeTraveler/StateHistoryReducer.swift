import Foundation

public final class StateRecord<State> {
    let state: State
    public let timestamp: Date = Date()
    
    init(state: State) {
        self.state = state
    }
}

public struct StateHistoryReducer<State>: Sendable {
    var reducer: @Sendable (inout [StateRecord<State>]) -> Void
    
    public init(reducer: @escaping @Sendable (inout [StateRecord<State>]) -> Void) {
        self.reducer = reducer
    }
    
    func callAsFunction(_ records: inout [StateRecord<State>]) {
        reducer(&records)
    }
}

public extension StateHistoryReducer {
    static var `default`: Self { timeDelta() }
    
    static var unlimited: Self {
        Self { _ in }
    }

    static func tail(maxCount: Int = 1000) -> Self {
        Self { $0.removeFirst(max(0, $0.count - maxCount)) }
    }

    static func timeDelta(maxCount: Int = 1000) -> Self {
        Self { records in
            while records.count > maxCount {
                var prev: StateRecord<State>?
                var smallestDelta: Double = .infinity
                var smallestIndex: Int?
                for index in records.indices {
                    let record = records[index]
                    if let prev {
                        let delta = record.timestamp.timeIntervalSince(prev.timestamp)
                        if delta < smallestDelta {
                            smallestDelta = delta
                            smallestIndex = index
                        }
                    }
                    
                    prev = record
                }
                
                if let smallestIndex {
                    records.remove(at: smallestIndex - 1)
                }
            }
        }
    }
}
