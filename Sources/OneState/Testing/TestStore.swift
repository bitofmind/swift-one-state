import Foundation
import AsyncAlgorithms
import Dependencies
import XCTestDynamicOverlay
import CustomDump

public final class TestStore<M: Model> where M.State: Equatable&Sendable {
    let store: Store<M>
    let access: TestAccess<M.State>
    let file: StaticString
    let line: UInt

    public typealias State = M.State

    /// Creates a store for testing.
    ///
    ///     TestStore<AppView>(initialState: .init()) {
    ///        $0.uuid = .incrementing
    ///        $0.locale = Locale(identifier: "en_US")
    ///     }
    ///
    /// - Parameter initialState:The store's initial state.
    /// - Parameter dependencies: The overriden dependencies of the store.
    ///
    public init(initialState: State, dependencies: @escaping (inout DependencyValues) -> Void = { _ in }, file: StaticString = #file, line: UInt = #line) {
        store = .init(initialState: initialState, dependencies: dependencies)
        access = TestAccess(state: initialState)

        self.file = file
        self.line = line
    }

    deinit {
        store.context.removeRecusively()
        
        for info in store.cancellations.activeTasks {
            XCTFail("Models of type `\(info.modelName)` have \(info.count) active tasks still running", file: file, line: line)
        }

        for event in access.eventUpdate.values {
            XCTFail("Event not handled: \(String(describing: event))", file: file, line: line)
        }

        if access.stateUpdate.values.count > 1 {
            let lastAsserted = access.lastAssertedState
            let actual = store.state
            let difference = diff(lastAsserted, actual, format: .proportional)
                .map { "\($0.indent(by: 4))\n\n(Last asserted: −, Actual: +)" }
            ??  """
                Last asserted:
                \(String(describing: lastAsserted).indent(by: 2))
                Actual:
                \(String(describing: actual).indent(by: 2))
                """

            XCTFail("""
                State not exhausted: …
                \(difference)
                """, file: file, line: line)
        }
    }
}

extension TestStore: Sendable where State: Sendable {}

extension TestStore: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        store.storeView
    }
}

public extension TestStore {
    var model: M {
        StoreAccess.with(access) {
            M(self)
        }
    }

    var state: State { store.state }
}

public extension TestStore {
    func exhaustEvents() {
        access.eventUpdate.consumeAll()
    }

    func exhaustTasks(timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async {
        let start = DispatchTime.now().uptimeNanoseconds
        var hasTimedout: Bool {
            start.distance(to: DispatchTime.now().uptimeNanoseconds) >= timeout
        }

        while true {
            let activeTasks = store.cancellations.activeTasks

            if activeTasks.isEmpty {
                break
            }

            if hasTimedout  {
                for info in activeTasks {
                    XCTFail("Models of type `\(info.modelName)` have \(info.count) active tasks still running", file: file, line: line)
                }
                break
            }

            await Task.yield()
        }
    }
}
