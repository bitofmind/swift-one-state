import SwiftUI

/// A store hold the state of an application or part of a applicaton
///
/// A store hold the while and only one state of the appliction
/// From its state or a sub-state that state models are insantiate to update
/// the state and drive the update of SwiftUI views
///
/// Typically you setup you store in your App scene:
///
///     struct MyApp: App {
///         @Store<AppView> var store = .init()
///
///         var body: some Scene {
///             WindowGroup {
///                 AppViewView(model: $store.model)
///             }
///         }
///     }
///
///  A store could also be statically setup for use in e.g. previews:
///
///     struct MainView_Previews: PreviewProvider {
///         @Store<MainModel> static var store = .init()
///
///         static var previews: some View {
///             MainView(model: $store.model)
///         }
///     }
@dynamicMemberLookup @propertyWrapper
public struct Store<Model: ViewModel>: DynamicProperty {
    @StateObject private var access = ModelAccess<Model.State>()
    private var viewContext = ViewContext()

    public typealias State = Model.State

    public let wrappedValue: State

    public init(wrappedValue: State) {
        self.wrappedValue = wrappedValue
    }

    public var projectedValue: Store {
        self
    }

    public mutating func update() {
        viewContext.context = access.context

        guard !access.isObservering else { return }

        access.context = viewContext.context ?? RootContext(state: wrappedValue)
        viewContext.context = access.context
        access.startObserve()
    }
}

public extension Store {
    init<T>(wrappedValue: T) where Model == EmptyModel<T> {
        self.wrappedValue = wrappedValue
    }

    var model: Model {
        Model(self)
    }
}

extension Store: StoreViewProvider {
    public var storeView: StoreView<State, State, Write> {
        .init(context: context, path: \.self, access: access)
    }
}

public extension Store {
    /// Access the the lastest update useful for debugging or initial state for state recording
    var latestUpdate: StateUpdate<State, State, Write> {
        context.latestUpdate
    }

    /// Used to override state when replaying recorded state
    var stateOverride: StateUpdate<State, State, Write>? {
        get { context.stateOverride }
        set { context.stateOverride = newValue }
    }
}

private extension Store {
    var context: RootContext<State> {
        if viewContext.context == nil { // Static use for previews
            viewContext.context = RootContext(state: wrappedValue)
        }
        return viewContext.context as! RootContext<State>
    }

    class ViewContext {
        var context: Context<State>!
    }
}
