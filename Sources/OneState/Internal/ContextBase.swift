import Foundation
import Dependencies

class ContextBase: HoldsLock, @unchecked Sendable {
    let lock = NSRecursiveLock()
    private(set) weak var parent: ContextBase?

    var _children: [AnyKeyPath: ContextBase] = [:]
    var _overrideChildren: [AnyKeyPath: ContextBase] = [:]
    @Locked var isOverrideContext = false
    @Locked var hasBeenRemoved = false

    private let _stateUpdates = AsyncPassthroughSubject<StateUpdate>()
    var stateUpdates: AsyncStream<StateUpdate> { _stateUpdates.stream() }

    struct EventInfo: @unchecked Sendable {
        var event: Any
        var path: AnyKeyPath
        var context: ContextBase
        var callContexts: [CallContext]
    }
    let _events = AsyncPassthroughSubject<EventInfo>()
    var events: AsyncStream<EventInfo> { _events.stream() }

    var dependencies: [(index: Int, apply: (inout DependencyValues) -> Void)] = []
    @Locked var properties: [Any] = []

    @TaskLocal static var current: ContextBase?

    @Locked var containers: [AnyKeyPath: () -> ()] = [:]
    @Locked var identities: [AnyKeyPath: AnyHashable] = [:]

    init(parent: ContextBase?) {
        self.parent = parent
        self.hasBeenRemoved = parent?.$hasBeenRemoved ?? false
    }

    deinit {
        removeRecursively()
    }

    func onRemoval() {
        cancellations.cancelAll(for: ContextCancellationKey.self, context: cancellationContext)

        self.hasBeenRemoved = true
        let parent = lock {
            defer { self.parent = nil }
            return self.parent
        }

        parent?.removeContext(self)
    }
    
    @discardableResult
    func assertActive(refreshContainers: Bool = false) -> Bool {
        if refreshContainers {
            parent?.updateContainers()
        }
        
        return !hasBeenRemoved
    }

    var regularChildren: [AnyKeyPath: ContextBase] {
        get {
            return lock { _children }
        }
        set {
            lock { _children = newValue }
        }
    }

    var _allChildren: [AnyKeyPath: ContextBase] {
        isStateOverridden ? _overrideChildren : _children
    }

    var allChildren: [AnyKeyPath: ContextBase] {
        get {
            lock { _allChildren }
        }
        set {
            let isStateOverridden = isStateOverridden
            lock {
                if isStateOverridden {
                    _overrideChildren = newValue
                } else {
                    _children = newValue
                }
            }
        }
    }

    func removeContext(_ contextToRemove: ContextBase) {
        lock {
            for (path, context) in _overrideChildren where context === contextToRemove {
                _overrideChildren[path] = nil
                return
            }

            for (path, context) in _children where context === contextToRemove {
                _children[path] = nil
                return
            }
        }
    }

    func removeRecursively() {
        guard !hasBeenRemoved else { return }
        
        onRemoval()

        for child in allChildren.values {
            child.removeRecursively()
        }
    }

    func cancelAllRecursively(for id: Any.Type) {
        cancellations.cancelAll(for: id, context: cancellationContext)

        for child in allChildren.values {
            child.cancelAllRecursively(for: id)
        }
    }

    var cancellationContext: ObjectIdentifier { .init(self) }

    private func notifyUpdate(_ update: StateUpdate) {
        guard !hasBeenRemoved else { return }
        _stateUpdates.yield(update)
    }

    func notifyAncestors(_ update: StateUpdate) {
        parent?.notifyAncestors(update)
        parent?.notifyUpdate(update)
    }

    func notifyDescendants(_ update: StateUpdate) {
        updateContainers()

        let (children, overrideChildren) = lock {
            (_children.values, _overrideChildren.values)
        }

        for child in children {
            child.notifyUpdate(update)
            child.notifyDescendants(update)
        }

        for child in overrideChildren {
            if update.isOverrideUpdate {
                child.notifyUpdate(update)
            }
            child.notifyDescendants(update)
        }
    }

    func isDescendant(of context: ContextBase) -> Bool {
        guard let parent, context !== self else { return false }

        if parent === context { return true }

        return parent.isDescendant(of: context)
    }

    func notify(_ update: StateUpdate) {
        notifyAncestors(update)
        notifyUpdate(update)
        notifyDescendants(update)
        
        updateContainers()
    }

    func updateContainers() {
        for container in containers.values {
            container()
        }
    }

    var isStateOverridden: Bool {
        fatalError()
    }

    func sendEvent(_ eventInfo: EventInfo, to receivers: EventReceivers) {
        fatalError()
    }

    var cancellations: Cancellations { fatalError() }
    var storePath: AnyKeyPath { fatalError() }

    func withLocalDependencies<Value>(_ operation: () -> Value) -> Value {
        Dependencies.withDependencies(from: self) {
            for (_, apply) in dependencies {
                apply(&$0)
            }
        } operation: {
            operation()
        }
    }

    func withDependencies<Value>(_ operation: () -> Value) -> Value { fatalError() }

    var typeDescription: String { fatalError() }
}

