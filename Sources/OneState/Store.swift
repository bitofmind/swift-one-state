import SwiftUI
import Combine

/// A store hold the state of an application or part of a applicaton
///
/// A store hold the while and only one state of the appliction
/// From its state or a sub-state that state models are insantiate to update
/// the state and drive the update of SwiftUI views
///
/// Typically you setup you store in your App scene:
///
///     struct MyApp: App {
///         @Store var store = AppView.State()
///
///         var body: some Scene {
///             WindowGroup {
///                 AppViewView(model: $store.viewModel(AppModel()))
///             }
///         }
///     }
///
///  A store could also be statically setup for use in e.g. previews:
///
///     struct MainView_Previews: PreviewProvider {
///         @Store static var store = MainModel.State()
///
///         static var previews: some View {
///             MainView(model: $store.viewModel(.init()))
///         }
///     }
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
    /// Access the the lastest update useful for debugging or initial state for state recording
    var latestUpdate: StateUpdate<State, State> {
        context.latestUpdate
    }

    /// Used to override state when replaying recorded state
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
        var context: RootContext<State>!
    }

    class ViewContext {
        var context: RootContext<State>!
    }
}
