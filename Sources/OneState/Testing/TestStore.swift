import Foundation
import AsyncAlgorithms
import Dependencies
import XCTestDynamicOverlay
import CustomDump

public final class TestStore<Models: ModelContainer> where Models.Container: Equatable&Sendable {
    let store: Store<Models>
    let access: TestAccess<State>
    let file: StaticString
    let line: UInt

    public typealias State = Models.Container

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
            access.fail("Models of type `\(info.modelName)` have \(info.count) active tasks still running", for: .tasks, file: file, line: line)
        }

        for event in access.eventUpdate.values {
            access.fail("Event `\(String(describing: event.event))` sent from `\(event.context.typeDescription)` was not handled", for: .events, file: file, line: line)
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
                """, for: .state, file: file, line: line)
        }

        store.context.removeRecursively()
    }
}

extension TestStore: Sendable where State: Sendable {}

extension TestStore: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        var view = store.storeView
        view.access = access
        return view
    }
}

public extension TestStore {
    var model: Models {
        Models(self)
    }
}

public extension TestStore {
    var state: State { store.state }

    var exhaustivity: Exhaustivity {
        get { access.lock { access.exhaustivity } }
        set { access.lock { access.exhaustivity = newValue } }
    }

    var showSkippedAssertions: Bool {
        get { access.lock { access.showSkippedAssertions } }
        set { access.lock { access.showSkippedAssertions = newValue } }
    }
}

public struct Exhaustivity: OptionSet, Equatable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
}

public extension Exhaustivity {
    static let state = Self(rawValue: 1 << 0)
    static let events = Self(rawValue: 1 << 1)
    static let tasks = Self(rawValue: 1 << 2)

    static let off: Self = []
    static let full: Self = [.state, .events, .tasks]
}

enum TestStoreScope {}
