import Foundation
import Combine

final class ChildContext<ParentState, State>: Context<State> {
    private let context: Context<ParentState>
    private let path: WritableKeyPath<ParentState, State>
    private var stateDidUpdateCancellable: AnyCancellable?

    init(context: Context<ParentState>, path: WritableKeyPath<ParentState, State>) {
        self.context = context
        self.path = path
        super.init(parent: context)
        
        stateDidUpdateCancellable = context.stateDidUpdate.sink { [weak self] update in
            self?.notifyStateUpdate(update)
        }
    }
    
    private func parentPath(for path: PartialKeyPath<State>) -> PartialKeyPath<ParentState> {
        (self.path as PartialKeyPath<ParentState>).appending(path: path)!
    }
        
    override func getCurrent(access: StoreAccess, path: PartialKeyPath<State>) -> Any {
        return context.getCurrent(access: access, path: parentPath(for: path))
    }
    
    override func getShared(shared: AnyObject, path:  PartialKeyPath<State>) -> Any {
        context.getShared(shared: shared, path: parentPath(for: path))

    }
    
    override func modify(access: StoreAccess, updateState: (inout State) throws -> Void) rethrows {
        try context.modify(access: access) { parent in
            try updateState(&parent[keyPath: path])
        }
    }
}
