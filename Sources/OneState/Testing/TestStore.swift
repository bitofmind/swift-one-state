import Foundation
import AsyncAlgorithms

public final class TestStore<M: Model> where M.State: Equatable&Sendable {
    let store: Store<M>
    let access: TestAccess<M.State>
    let tasks: [Task<(), Never>]

    public typealias State = M.State

    public init(initialState: State, environments: [Any] = [], onTestFailure: @escaping @Sendable (TestFailure<State>) async -> Void) {
        store = .init(initialState: initialState, environments: environments)

        let channel = AsyncChannel<()>()
        let initTask = Task {
            let _ = await channel.first { _ in true }
        }

        access = TestAccess(
            state: initialState,
            initTask: initTask,
            onTestFailure: onTestFailure
        )

        var tasks = [Task<(), Never>] ()
        tasks.append(Task { [weak access, store] in
            var first = true
            access?.stateUpdate.receiveSkipDuplicates(initialState)

            for await state in store.changes {
                access?.stateUpdate.receiveSkipDuplicates(state)

                guard first else { continue }
                first = false

                Task {
                    await channel.send(())
                }
            }
        })

        tasks.append(Task { [weak access, store] in
            for await event in store.context.events {
                access?.eventUpdate.receive(event)
            }
        })

        self.tasks = tasks
    }

    deinit {
        for task in tasks {
            task.cancel()
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
    func updateEnvironment<Value>(_ value: Value) {
        store.updateEnvironment(value)
    }
}

public extension TestStore {
    convenience init<T>(initialState: T, environments: [Any] = [], onTestFailure: @escaping @Sendable (TestFailure<State>) async -> Void) where M == EmptyModel<T> {
        self.init(initialState: initialState, environments: environments, onTestFailure: onTestFailure)
    }

    var model: M {
        StoreAccess.$current.withValue(Weak(value: access)) {
            M(self)
        }
    }
}

public struct ExhaustedFlags: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let state = Self(rawValue: 1 << 0)
    public static let events = Self(rawValue: 1 << 1)
    public static let tasks = Self(rawValue: 1 << 2)
    public static let all: Self = [state, events, tasks]
}

public extension TestStore {
    func assertExhausted(_ flags: ExhaustedFlags = .all, timeoutNanoseconds timeout: UInt64 = NSEC_PER_SEC, file: StaticString = #file, line: UInt = #line) async {
        let start = DispatchTime.now().uptimeNanoseconds
        var hasTimedout: Bool {
            start.distance(to: DispatchTime.now().uptimeNanoseconds) >= timeout
        }

        while flags.contains(.tasks) {
            let activeTasks = store.activeTasks

            if activeTasks.isEmpty {
                break
            }

            if hasTimedout  {
                for info in activeTasks {
                    await access.onTestFailure(.tasksAreStillRunning(modelName: info.modelName, taskCount: info.count), file: file, line: line)
                }
                break
            }

            await Task.yield()
        }

        while flags.contains(.events) {
            let events = access.eventUpdate.values
            if events.isEmpty { break }

            if hasTimedout {
                for event in events {
                    await access.onTestFailure(.eventNotExhausted(event: event.event), file: file, line: line)
                }
                break
            }

            await Task.yield()
        }

        while flags.contains(.state) {
            await Task { [store] in
                while store.isUpdateInProgress {
                    await Task.yield()
                }
            }.value

            if access.stateUpdate.values.count == 1 { break }

            if hasTimedout {
                await access.onTestFailure(.stateNotExhausted(lastAsserted: access.lastAssertedState, actual: store.state), file: file, line: line)
                break
            }

            await Task.yield()
        }
    }
}
