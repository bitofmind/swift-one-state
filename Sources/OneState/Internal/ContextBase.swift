import Foundation

class ContextBase: HoldsLock, @unchecked Sendable {
    var lock = Lock()
    private(set) weak var parent: ContextBase?

    var _children: [AnyKeyPath: ContextBase] = [:]
    var _overrideChildren: [AnyKeyPath: ContextBase] = [:]
    @Locked var isOverrideContext: Bool = false

    let stateUpdates = AsyncPassthroughSubject<AnyStateChange>()

    struct EventInfo: @unchecked Sendable {
        var event: Any
        var path: AnyKeyPath
        var context: ContextBase
        var callContexts: [CallContext]
    }
    let events = AsyncPassthroughSubject<EventInfo>()

    @Locked var dependencies: [ObjectIdentifier: Any] = [:]
    @Locked var properties: [Any] = []

    @TaskLocal static var current: ContextBase?

    let contextCancellationKey = UUID()

    @Locked var containers: [AnyKeyPath: (AnyStateChange) -> ()] = [:]

    init(parent: ContextBase?) {
        self.parent = parent
    }

    deinit {
        onRemoval()
    }

    func onRemoval() {
        cancellations.cancelAll(for: contextCancellationKey)

        parent?.removeContext(self)
        parent = nil
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

    func removeRecusively() {
        onRemoval()

        for child in allChildren.values {
            child.removeRecusively()
        }
    }

    func notifyAncestors(_ update: AnyStateChange) {
        parent?.notifyAncestors(update)
        parent?.stateUpdates.yield(update)
    }

    func notifyDescendants(_ update: AnyStateChange) {
        let (children, overrideChildren) = lock {
            (_children.values, _overrideChildren.values)
        }

        for child in children {
            child.stateUpdates.yield(update)
            child.notifyDescendants(update)
        }

        for child in overrideChildren {
            if update.isOverrideUpdate {
                child.stateUpdates.yield(update)
            }
            child.notifyDescendants(update)
        }
    }

    func notify(_ update: AnyStateChange) {
        notifyAncestors(update)
        stateUpdates.yield(update)
        notifyDescendants(update)

        for container in containers.values {
            container(update)
        }
    }

    var isStateOverridden: Bool {
        fatalError()
    }

    func sendEvent(_ eventInfo: EventInfo) {
        fatalError()
    }

    var cancellations: Cancellations { fatalError() }

    func diff(for change: AnyStateChange, at path: AnyKeyPath) -> String? { fatalError() }

    var storePath: AnyKeyPath { fatalError() }
}

