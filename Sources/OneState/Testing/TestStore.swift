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
    /// - Parameter dependencies: The overridden dependencies of the store.
    ///
    public init(initialState: State, dependencies: @escaping (inout DependencyValues) -> Void = { _ in }, file: StaticString = #file, line: UInt = #line) {
        store = .init(initialState: initialState, dependencies: dependencies)
        access = TestAccess(state: initialState)

        self.file = file
        self.line = line
    }

    deinit {
        store.cancellations.cancelAll(for: TestStoreScope.self)
        store.context.cancelActiveContextRecursively()

        for info in store.cancellations.activeTasks {
            access.fail("Models of type `\(info.modelName)` have \(info.count) active tasks still running", file: file, line: line)
        }

        for event in access.eventUpdate.values {
            access.fail("Event `\(String(describing: event.event))` sent from `\(event.context.typeDescription)` was not handled", file: file, line: line)
        }

        let lastAsserted = access.lastAssertedState
        let actual = store.state
        if access.stateUpdate.values.count > 0, lastAsserted != actual {
            let difference = diff(lastAsserted, actual, format: .proportional)
                .map { "\($0.indent(by: 4))\n\n(Last asserted: −, Actual: +)" }
            ??  """
                Last asserted:
                \(String(describing: lastAsserted).indent(by: 2))
                Actual:
                \(String(describing: actual).indent(by: 2))
                """

            access.fail("""
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

    var exhaustivity: Exhaustivity {
        get { access.lock { access.exhaustivity } }
        set { access.lock { access.exhaustivity = newValue } }
    }
}

public enum Exhaustivity: Equatable, Sendable {
  case on
  case off(showSkippedAssertions: Bool)
  public static let off = off(showSkippedAssertions: false)
}

public extension TestStore {
    func exhaustTasks(timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async {
        store.cancellations.cancelAll(for: TestStoreScope.self)
        store.context.cancelActiveContextRecursively()

        let start = DispatchTime.now().uptimeNanoseconds
        var hasTimedOut: Bool {
            start.distance(to: DispatchTime.now().uptimeNanoseconds) >= timeout
        }

        while true {
            let activeTasks = store.cancellations.activeTasks

            if activeTasks.isEmpty {
                break
            }

            if hasTimedOut  {
                for info in activeTasks {
                    access.fail("Models of type `\(info.modelName)` have \(info.count) active tasks still running", file: file, line: line)
                }
                break
            }

            await Task.yield()
        }
    }
}

enum TestStoreScope {}
