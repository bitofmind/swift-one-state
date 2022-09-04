/// A protocol indicating that an activity or action supports cancellation.
public protocol Cancellable {
    /// Cancel the activity.
    func cancel()

    /// Cancel the activity when `cancelAll(for: key)` is called for the  provided `key`
    /// If `cancelInFlight` is true,  any previous activty set up to be cancelled for `key`
    /// is first cancelled.
    ///
    ///     model.task { ... }.cancel(for: myKey)
    @discardableResult
    func cancel(for key: AnyHashable, cancelInFlight: Bool) -> Self
}

public extension Cancellable {
    @discardableResult
    func cancel(for key: AnyHashable) -> Self {
        cancel(for: key, cancelInFlight: false)
    }

    @discardableResult
    func cancel(for id: Any.Type, cancelInFlight: Bool = false) -> Self {
        cancel(for: ObjectIdentifier(id), cancelInFlight: cancelInFlight)
    }
}

/// Activites created while the context is active ( while perform is execute or any nested tasks) will be cancelllable by the provided `key`.
public func withCancellationContext(_ key: AnyHashable, perform: () -> Void) {
    AnyCancellable.$contexts.withValue(AnyCancellable.contexts + [key]) {
        perform()
    }
}

public func withCancellationContext(_ id: Any.Type, perform: () -> Void) {
    withCancellationContext(ObjectIdentifier(id), perform: perform)
}

struct AnyCancellable: Cancellable, InternalCancellable {
    let cancellations: Cancellations
    var id: Int
    private var _onCancel: @Sendable () -> Void

    init(cancellations: Cancellations, onCancel: @escaping @Sendable () -> Void) {
        self.cancellations = cancellations
        id = cancellations.nextId
        _onCancel = onCancel
        cancellations.register(self)
    }

    func onCancel() {
        _onCancel()
    }

    public func cancel() {
        cancellations.cancel(self)
    }

    @discardableResult
    public func cancel(for key: AnyHashable, cancelInFlight: Bool) -> Self {
        cancellations.cancel(self, for: key, cancelInFlight: cancelInFlight)
        return self
    }

    @TaskLocal static var contexts: [AnyHashable] = []
}

struct TaskCancellable: Cancellable, InternalCancellable {
    var id: Int
    let cancellations: Cancellations
    let task: Task<Void, Error>
    let name: String

    init<M: Model>(model: M, task: @escaping @Sendable (@escaping @Sendable () -> Void) -> Task<Void, Error>) {
        let cs = model.context.cancellations
        self.cancellations = cs
        let id = cancellations.nextId
        self.id = id
        self.task = task {
            _ = cs.unregister(id)
        }
        name = model.typeDescription
        cs.register(self)
    }

    func onCancel() {
        task.cancel()
    }

    public func cancel() {
        cancellations.cancel(self)
    }

    @discardableResult
    public func cancel(for key: AnyHashable, cancelInFlight: Bool) -> Self {
        cancellations.cancel(self, for: key, cancelInFlight: cancelInFlight)
        return self
    }
}

protocol InternalCancellable {
    var cancellations: Cancellations { get }
    var id: Int { get }
    func onCancel()
}

final class Cancellations: @unchecked Sendable {
    fileprivate var lock = Lock()
    fileprivate var registered: [Int: InternalCancellable] = [:]
    fileprivate var keyed: [AnyHashable: [Int]] = [:]

    func cancel(_ c: InternalCancellable) {
        unregister(c.id)?.onCancel()
    }

    func cancel(_ c: InternalCancellable, for key: AnyHashable, cancelInFlight: Bool) {
        if cancelInFlight {
            cancelAll(for: key)
        }

        lock {
            guard registered[c.id] != nil else { return }
            keyed[key, default: []].append(c.id)
        }
    }

    func register(_ c: InternalCancellable) {
        lock {
            registered[c.id] = c

            for key in AnyCancellable.contexts {
                keyed[key, default: []].append(c.id)
            }
        }
    }

    func unregister(_ id: Int) -> InternalCancellable? {
        lock {
            registered.removeValue(forKey: id)
        }
    }

    func cancelAll(for key: AnyHashable) {
        lock {
            (keyed.removeValue(forKey: key) ?? []).compactMap { id in
                registered.removeValue(forKey: id)
            }
        }.forEach {
            $0.onCancel()
        }
    }

    var activeTasks: [(modelName: String, count: Int)] {
        lock {

            registered.values.reduce(into: [String: Int]()) { dict, c in
                if let task = c as? TaskCancellable {
                    dict[task.name, default: 0] += 1
                }
            }.map { (modelName: $0.key, count: $0.value) }
        }
    }

    var _nextId = 0
    var nextId: Int {
        lock {
            _nextId += 1
            return _nextId
        }
    }
}
