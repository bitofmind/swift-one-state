import Foundation

/// A protocol indicating that an activity or action supports cancellation.
public protocol Cancellable {
    /// Cancel the activity.
    func cancel()

    /// Cancel the activity of a model when  when `model.cancelAll(for: key)` is called for the  provided `key`
    /// If `cancelInFlight` is true,  any previous activity set up to be cancelled for `key`
    /// is first cancelled.
    ///
    ///     model.task { ... }.cancel(for: myKey)
    @discardableResult
    func cancel(for key: some Hashable&Sendable, cancelInFlight: Bool) -> Self
}

public extension Cancellable {
    @discardableResult
    func cancel(for key: some Hashable&Sendable) -> Self {
        cancel(for: key, cancelInFlight: false)
    }

    @discardableResult
    func cancel(for id: Any.Type, cancelInFlight: Bool = false) -> Self {
        cancel(for: ObjectIdentifier(id), cancelInFlight: cancelInFlight)
    }

    /// Cancels any previously active task (using a key based of source location).
    ///
    ///     func onReload() {
    ///         task { ... }.cancelInFlight()
    ///     }
    @discardableResult
    func cancelInFlight(file: String = #fileID, line: Int = #line) -> Self {
        cancel(for: FileAndLine(file: file, line: line), cancelInFlight: true)
    }
}

/// Activities created while the context is active (while perform is executed or any nested tasks) will be cancellable by the provided `key`.
///
///     withCancellationContext(myKey) {
///         task { }
///         forEach { }
///     }
///
///     cancelAll(for: myKey)
///
public func withCancellationContext(_ key: some Hashable&Sendable, perform: () throws -> Void) rethrows {
    try AnyCancellable.$contexts.withValue(AnyCancellable.contexts + [CancellableKey(key: key)]) {
        try perform()
    }
}

public func withCancellationContext(_ key: some Hashable&Sendable, perform: () async throws -> Void) async rethrows {
    try await AnyCancellable.$contexts.withValue(AnyCancellable.contexts + [CancellableKey(key: key)]) {
        try await perform()
    }
}

/// Activities created while the context is active (while perform is executed or any nested tasks) will be cancellable by the provided `id`.
///
///     withCancellationContext(MyKey.self) {
///         task { }
///         forEach { }
///     }
///
///     cancelAll(for: MyKey.self)
///
public func withCancellationContext(_ id: Any.Type, perform: () throws -> Void) rethrows {
    try withCancellationContext(ObjectIdentifier(id), perform: perform)
}

public func withCancellationContext(_ id: Any.Type, perform: () async throws -> Void) async rethrows {
    try await withCancellationContext(ObjectIdentifier(id), perform: perform)
}

struct CancellableKey: Hashable, @unchecked Sendable {
    var key: AnyHashable
}

struct FileAndLine: Hashable, Sendable {
    var file: String
    var line: Int
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
    public func cancel(for key: some Hashable&Sendable, cancelInFlight: Bool) -> Self {
        cancellations.cancel(self, for: key, cancelInFlight: cancelInFlight)
        return self
    }

    @TaskLocal static var contexts: [CancellableKey] = []
}

final class TaskCancellable: Cancellable, InternalCancellable {
    var id: Int
    var cancellations: Cancellations
    var task: Task<Void, Error>!
    var name: String
    var lock = Lock()
    var hasBeenCancelled = false

    init(name: String, cancellations: Cancellations, task: @escaping @Sendable (@escaping @Sendable () -> Void) -> Task<Void, Error>) {
        self.cancellations = cancellations
        let id = cancellations.nextId
        self.id = id
        self.name = name
        self.task = nil

        cancellations.register(self)

        lock {
            guard !self.hasBeenCancelled else { return }
            self.task = task {
                _ = cancellations.unregister(id)
            }
        }
    }

    func onCancel() {
        lock {
            self.task?.cancel()
            self.hasBeenCancelled = true
        }
    }

    public func cancel() {
        cancellations.cancel(self)
    }

    @discardableResult
    public func cancel(for key: some Hashable&Sendable, cancelInFlight: Bool) -> Self {
        cancellations.cancel(self, for: key, cancelInFlight: cancelInFlight)
        return self
    }
}

extension TaskCancellable {
    convenience init(name: String, cancellations: Cancellations, priority: TaskPriority? = nil, operation: @escaping @Sendable () async throws -> Void, `catch`: (@Sendable (Error) -> Void)? = nil) {
        self.init(name: name, cancellations: cancellations) { onDone in
            Task(priority: priority) {
                do {
                    try await CallContext.$streamContexts.withValue(.init([])) {
                        try await inViewModelContext {
                            defer { onDone() }

                            guard !Task.isCancelled else { return }
                            try await operation()
                        }
                    }
                } catch {
                    `catch`?(error)
                }
            }
        }
    }
}

struct EmptyCancellable: Cancellable {
    func cancel() {}
    
    func cancel(for key: some Hashable & Sendable, cancelInFlight: Bool) -> EmptyCancellable { self }
}

protocol InternalCancellable {
    var cancellations: Cancellations { get }
    var id: Int { get }
    func onCancel()
}

final class Cancellations: @unchecked Sendable {
    fileprivate var lock = Lock()
    fileprivate var registered: [Int: InternalCancellable] = [:]
    fileprivate var keyed: [CancellableKey: [Int]] = [:]

    func cancel(_ c: InternalCancellable) {
        unregister(c.id)?.onCancel()
    }

    func cancel<Key: Hashable&Sendable>(_ c: InternalCancellable, for key: Key, cancelInFlight: Bool) {
        if cancelInFlight {
            cancelAll(for: key)
        }

        lock {
            guard registered[c.id] != nil else { return }
            keyed[.init(key: key), default: []].append(c.id)
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

    func cancelAll(for key: some Hashable&Sendable) {
        lock {
            (keyed.removeValue(forKey: .init(key: key)) ?? []).compactMap { id in
                registered.removeValue(forKey: id)
            }
        }.forEach {
            $0.onCancel()
        }
    }

    func cancelAll(for id: Any.Type) {
        cancelAll(for: ObjectIdentifier(id))
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
