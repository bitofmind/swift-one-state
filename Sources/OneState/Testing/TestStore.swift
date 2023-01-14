import Foundation
import AsyncAlgorithms

public final class TestStore<M: Model> where M.State: Equatable&Sendable {
    let store: Store<M>
    let access: TestAccess<M.State>
    let file: StaticString
    let line: UInt

    public typealias State = M.State

    public init(initialState: State, file: StaticString = #file, line: UInt = #line, onTestFailure: @escaping @Sendable (TestFailure<State>) -> Void = assertNoFailure) {
        store = .init(initialState: initialState)

        access = TestAccess(
            state: initialState,
            onTestFailure: onTestFailure
        )

        self.file = file
        self.line = line
    }

    deinit {
        store.context.removeRecusively()
        
        for info in store.cancellations.activeTasks {
            access.onTestFailure(.tasksAreStillRunning(modelName: info.modelName, taskCount: info.count), file: file, line: line)
        }

        for event in access.eventUpdate.values {
            access.onTestFailure(.eventNotExhausted(event: event.event), file: file, line: line)
        }

        if access.stateUpdate.values.count > 1 {
            access.onTestFailure(.stateNotExhausted(lastAsserted: access.lastAssertedState, actual: store.state), file: file, line: line)
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
    func dependency<Value>(_ path: WritableKeyPath<ModelDependencyValues, Value>, _ value: Value) -> Self {
        store.updateDependency(path, value)
        return self
    }
}

public extension TestStore {
    var model: M {
        StoreAccess.$current.withValue(Weak(value: access)) {
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
                    access.onTestFailure(.tasksAreStillRunning(modelName: info.modelName, taskCount: info.count), file: file, line: line)
                }
                break
            }

            await Task.yield()
        }
    }
}
