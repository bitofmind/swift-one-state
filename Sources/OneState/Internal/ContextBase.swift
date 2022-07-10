class ContextBase: HoldsLock, @unchecked Sendable {
    var lock = Lock()
    private(set) weak var parent: ContextBase?

    private var _children: [AnyKeyPath: ContextBase] = [:]
    private var _overrideChildren: [AnyKeyPath: ContextBase] = [:]

    let stateUpdates = AsyncPassthroughSubject<AnyStateChange>()

    typealias Event = (event: Any, path: AnyKeyPath, context: ContextBase, callContext: CallContext?)
    let events = AsyncPassthroughSubject<Event>()

    @Locked var environments: Environments = [:]

    @Locked var propertyIndex = 0
    @Locked var properties: [Any] = []
    @Locked var cancellables: [Cancellable] = []
    @Locked var isForTesting = false
    @Locked var hasBeenRemoved = false
    @Locked var refCount = 0

    @TaskLocal static var current: ContextBase?

    init(parent: ContextBase?) {
        self.parent = parent
        if let parent = parent {
            isForTesting = parent.isForTesting
        }
    }

    deinit {
        onRemoval()
    }

    var regularChildren: [AnyKeyPath: ContextBase] {
        get {
            return lock { _children }
        }
        set {
            lock { _children = newValue }
        }
    }

    var allChildren: [AnyKeyPath: ContextBase] {
        get {
            let isStateOverridden = isStateOverridden
            return lock { isStateOverridden ? _overrideChildren : _children }
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

    func removeChildren() {
        let children: [ContextBase] = lock {
            Array(_overrideChildren.values) + _children.values
        }

        for child in children {
            child.onRemovalFromView()
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

    func sendEvent(_ event: Any, path: AnyKeyPath, context: ContextBase, callContext: CallContext?) {
        fatalError()
    }
}

extension ContextBase {
    var isOverrideStore: Bool {
        lock {
            parent?._overrideChildren.values.contains { $0 === self } ?? false
        }
    }

    func retainFromView() {
        if isStateOverridden && !isOverrideStore { return }

        refCount += 1
    }

    func releaseFromView() {
        if isStateOverridden && !isOverrideStore { return }

        refCount -= 1
        if refCount == 0 {
            onRemovalFromView()
        }
    }
}

private extension ContextBase {
    func onRemovalFromView() {
        onRemoval()
    }

    func onRemoval() {
        guard !hasBeenRemoved else {
            return
        }

        let cancellables = self.cancellables
        guard cancellables.isEmpty else {
            self.cancellables.removeAll()
            for cancellable in cancellables {
                cancellable.cancel()
            }

            return onRemoval() // Call recursively in case more actions has been added while cancelling
        }

        if parent != nil {
            hasBeenRemoved = true
        }

        removeChildren()
        if let parent = parent {
            parent.removeChildStore(self)
        }
    }
}
