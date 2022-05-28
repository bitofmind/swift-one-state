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
    
    override func getCurrent<T>(atPath path: KeyPath<State, T>, access: StoreAccess?) -> T {
        context.getCurrent(atPath: self.path.appending(path: path), access: access)
    }
    
    override func getShared<T>(shared: AnyObject, path: KeyPath<State, T>) -> T {
        context.getShared(shared: shared, path: self.path.appending(path: path))
    }
    
    override func _modify(fromContext: ContextBase, access: StoreAccess?, updateState: (inout State) throws -> Void) rethrows {
        try context._modify(fromContext: fromContext, access: access) { parent in
            try updateState(&parent[keyPath: path])
        }
    }
    
    override func sendEvent<T>(_ event: Any, path: KeyPath<State, T>, viewModel: Any, callContext: CallContext?) {
        super.sendEvent(event, path: path, viewModel: viewModel, callContext: callContext)
        context.sendEvent(event, path: self.path.appending(path: path), viewModel: viewModel, callContext: callContext)
    }
}
