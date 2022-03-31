import Foundation
import Combine

final class ChildContext<ParentState, State>: Context<State> {
    private let context: Context<ParentState>
    private let path: WritableKeyPath<ParentState, State>

    init(context: Context<ParentState>, path: WritableKeyPath<ParentState, State>) {
        self.context = context
        self.path = path
        super.init(parent: context)
    }
    
    override func getCurrent<T>(access: StoreAccess, path: KeyPath<State, T>) -> T {
        context.getCurrent(access: access, path: self.path.appending(path: path))
    }
    
    override func getShared<T>(shared: AnyObject, path: KeyPath<State, T>) -> T {
        context.getShared(shared: shared, path: self.path.appending(path: path))
    }
    
    override func _modify(access: StoreAccess, updateState: (inout State) throws -> Void) rethrows -> AnyStateChange? {
        let update = try context._modify(access: access) { parent in
            try updateState(&parent[keyPath: path])
        }
        
        if let update = update {
            notifyObservedStateUpdate(update)
        }
        
        return update
    }
}
