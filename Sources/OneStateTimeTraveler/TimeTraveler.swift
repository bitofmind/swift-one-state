import Foundation
import OneState
import AsyncAlgorithms
import Dependencies

public struct TimeTraveler: Sendable {
    public var stateStream: @Sendable () -> AsyncStream<OverrideState?>
    public var setOverride: @Sendable (Int?) -> Void
    public var printDiff: @Sendable (Int) -> Void
}

public struct OverrideState: Equatable, Codable, Sendable {
    public var index: Int
    public var count: Int
}
