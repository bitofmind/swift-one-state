import Foundation
import Combine

class ContextBase: HoldsLock {
    var lock = Lock()
    private(set) weak var parent: ContextBase?

    private var _children: [AnyKeyPath: ContextBase] = [:]
    private var _overrideChildren: [AnyKeyPath: ContextBase] = [:]
    
    let stateDidUpdate: PassthroughSubject<AnyStateChange, Never>
    let observedStateDidUpdate = PassthroughSubject<(), Never>()

    @Locked var environments: Environments = [:]
    @Locked var propertyIndex = 0
    @Locked var properties: [Any] = []
    @Locked var anyCancellables: Set<AnyCancellable> = []
    @Locked var isFullyInitialized: Bool = false
    @Locked var isForTesting = false
    @Locked var hasBeenRemoved = false
    @Locked var refCount = 0

    @TaskLocal static var current: ContextBase?

    init(parent: ContextBase?) {
        self.parent = parent
        if let parent = parent {
            stateDidUpdate = parent.stateDidUpdate
            isForTesting = parent.isForTesting
            if isForTesting {
                environments = parent.environments
            }
        } else {
            stateDidUpdate = .init()
        }
    }
    
    deinit {
        onRemoval()
    }
    
    var children: [AnyKeyPath: ContextBase] {
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
    
    func removeChildStore(_ storeTorRemove: ContextBase) {
        lock {
            for (path, context) in _overrideChildren where context === storeTorRemove {
                _overrideChildren[path] = nil
                return
            }
            
            for (path, context) in _children where context === storeTorRemove {
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
    
    func notifyStateUpdate(_ update: AnyStateChange) {
        fatalError()
    }
    
    var isStateOverridden: Bool {
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
        refCount += 1
    }
    
    func releaseFromView() {
        refCount -= 1
        if refCount == 0 {
            onRemovalFromView()
        }
    }
}

private extension ContextBase {
    func onRemovalFromView() {
        if isStateOverridden && !isOverrideStore { return }
        
        onRemoval()
    }
    
    func onRemoval() {
        guard !hasBeenRemoved else {
            return
        }
        
        let cancellables = anyCancellables
        guard cancellables.isEmpty else {
            anyCancellables.removeAll()
            for cancellable in cancellables {
                cancellable.cancel()
            }
            
            return onRemoval() // Call recursively in case more actions has been added while cancelling
        }

        hasBeenRemoved = true
                            
        removeChildren()
        if let parent = parent {
            parent.removeChildStore(self)
        } else {
            _overrideChildren.removeAll()
            children.removeAll()
        }
    }
}

