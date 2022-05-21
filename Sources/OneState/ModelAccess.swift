import Foundation
import Combine

class ModelAccess<State>: StoreAccess, ObservableObject {
    var context: Context<State>!
    var cancellable: AnyCancellable?
    var lock = Lock()
    var observedStates: [AnyKeyPath: (AnyStateChange) -> Bool] = [:]

    deinit {
        context?.releaseFromView()
    }

    override func willAccess<Root, State>(path: KeyPath<Root, State>, context: Context<Root>, isSame: @escaping (State, State) -> Bool) {
        lock {
            if observedStates.index(forKey: path) == nil {
                observedStates[path] = { [weak context] update in
                    guard let context = context else { return false }

                    return isSame(
                        context.getShared(shared: update.current, path: path),
                        context.getShared(shared: update.previous, path: path)
                    )
                }
            }
        }
    }

    override var allowAccessToBeOverridden: Bool { true }

    var isObservering: Bool {
        cancellable != nil
    }

    func startObserve() {
        cancellable?.cancel()
        var wasStateOverriden = context.isStateOverridden
        cancellable = context.stateDidUpdate.sink { [weak self] update in
            guard let self = self, update.isStateOverridden == update.isOverrideUpdate else { return }

            let wasUpdated: Bool = self.lock {
                if wasStateOverriden != update.isStateOverridden {
                    wasStateOverriden = update.isStateOverridden
                    return true
                }

                for equal in self.observedStates.values {
                    guard equal(update) else {
#if false
                        let previous = self.context.getShared(shared: update.previous, path: \State.self)
                        let current = self.context.getShared(shared: update.current, path: \State.self)
                        print("previous", previous)
                        print("current", current)
#endif
                        return true
                    }
                }
                return false
            }

            guard wasUpdated else { return }

            if Thread.isMainThread {
                self.objectWillChange.send()
            } else {
                DispatchQueue.main.async {
                    self.objectWillChange.send()
                }
            }
        }
    }
}
