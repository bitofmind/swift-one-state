class ContextBase: HoldsLock, @unchecked Sendable {
    var lock = Lock()
    private(set) weak var parent: ContextBase?

    var _children: [AnyKeyPath: ContextBase] = [:]
    var _overrideChildren: [AnyKeyPath: ContextBase] = [:]

    let stateUpdates = AsyncPassthroughSubject<AnyStateChange>()

    struct EventInfo: @unchecked Sendable {
        var  event: Any
        var  path: AnyKeyPath
        var context: ContextBase
        var callContexts: [CallContext]
    }
    let events = AsyncPassthroughSubject<EventInfo>()

    @Locked var environments: Environments = [:]

    @Locked var propertyIndex = 0
    @Locked var properties: [Any] = []
    @Locked var cancellables: [Cancellable] = []
    @Locked var activationCancellables: [Cancellable] = []
    @Locked var activationRefCount = 0

    @TaskLocal static var current: ContextBase?
    @TaskLocal static var isInActivationContext = false

    init(parent: ContextBase?) {
        self.parent = parent
    }

    deinit {
        let cancellables = self.cancellables + self.activationCancellables
        for cancellable in cancellables {
            cancellable.cancel()
        }

        if let parent = parent {
            parent.removeChildStore(self)
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

    func removeChildStore(_ storeToRemove: ContextBase) {
        lock {
            for (path, context) in _overrideChildren where context === storeToRemove {
                _overrideChildren[path] = nil
                return
            }

            for (path, context) in _children where context === storeToRemove {
                _children[path] = nil
                return
            }

            fatalError("Failed to remove context")
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

    func pushTask(_ info: TaskInfo) {
        fatalError()
    }

    func popTask(_ info: TaskInfo) {
        fatalError()
    }
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
            let cancellables = self.activationCancellables
            self.activationCancellables.removeAll()
            for cancellable in cancellables {
                cancellable.cancel()
            }
        }
    }
}
