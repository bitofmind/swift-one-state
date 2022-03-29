import SwiftUI
import Combine

@dynamicMemberLookup @propertyWrapper
public struct Store<State>: DynamicProperty {
    @StateObject private var shared = Shared()
    private var viewContext = ViewContext()

    public let wrappedValue: State
    
    public init(wrappedValue: State) {
        self.wrappedValue = wrappedValue
    }
    
    public var projectedValue: Store<State> {
        self
    }
    
    public func update() {
        if shared.context == nil {
            shared.context = viewContext.context ?? .init(state: wrappedValue)
            
            shared.cancellable = shared.context.observedStateDidUpdate.sink { [weak shared] in
                shared?.objectWillChange.send()
            }
        }
        
        viewContext.context = shared.context
    }
}

extension Store: StoreViewProvider {
    public var storeView: StoreView<State, State> {
        .init(context: context, path: \.self, access: .fromView)
    }
}

public extension Store {
    var latestUpdate: StateUpdate<State, State> {
        context.latestUpdate
    }

    var stateOverride: StateUpdate<State, State>? {
        get { context.stateOverride }
        set { context.stateOverride = newValue }
    }
}

private extension Store {
    var context: RootContext<State> {
        if viewContext.context == nil { // Static use for previews
            viewContext.context = .init(state: wrappedValue)
        }
        return viewContext.context
    }
    
    class Shared: ObservableObject {
        var cancellable: AnyCancellable?
        var context: RootContext<State>! {
            willSet {
                context?.releaseFromView()
                newValue.retainFromView()
            }
        }
        
        deinit {
            context.releaseFromView()
        }
    }

    class ViewContext {
        var context: RootContext<State>!
    }
}
