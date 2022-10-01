import Foundation

class ContextBase: HoldsLock, @unchecked Sendable {
    var lock = Lock()
    private(set) weak var parent: ContextBase?

    var _children: [AnyKeyPath: ContextBase] = [:]
    var _overrideChildren: [AnyKeyPath: ContextBase] = [:]

    let stateUpdates = AsyncPassthroughSubject<AnyStateChange>()

    struct EventInfo: @unchecked Sendable {
        var event: Any
        var path: AnyKeyPath
        var context: ContextBase
        var callContexts: [CallContext]
    }
    let events = AsyncPassthroughSubject<EventInfo>()

    @Locked var dependencies: [ObjectIdentifier: Any] = [:]

    @Locked var propertyIndex = 0
    @Locked var properties: [Any] = []
    @Locked var activationRefCount = 0

    @TaskLocal static var current: ContextBase?

    let contextCancellationKey = UUID()
    let activationCancellationKey = UUID()

    init(parent: ContextBase?) {
        self.parent = parent
    }

    deinit {
        cancellations.cancelAll(for: contextCancellationKey)
        cancellations.cancelAll(for: activationCancellationKey)

        if let parent = parent {
            parent.removeContext(self)
        }
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

            fatalError("Failed to remove context")
        }
    }

    func removeRecusively() {
        parent?.removeContext(self)
        parent = nil

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

extension ContextBase {
    var isOverrideStore: Bool {
        lock {
            parent?._overrideChildren.values.contains { $0 === self } ?? false
        }
    }

    func activateRetain() {
        if isStateOverridden && !isOverrideStore { return }

        activationRefCount += 1
    }

    func activationRelease() {
        if isStateOverridden && !isOverrideStore { return }

        activationRefCount -= 1
        if activationRefCount == 0 {
            cancellations.cancelAll(for: activationCancellationKey)
        }
    }
}
