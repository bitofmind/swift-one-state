import SwiftUI
import Combine

/// Declares a view models state
///
/// To access a models state from its injected store (view `viewModel()`),
/// a view model must declare a state property using `@ModelState`:
///
///     struct MyModel: ViewModel {
///         @ModelState state: State
///     }
///
/// Any access to a models state goes view the this property.
/// If you like to access a view into the state's store, e.g. for creating a
/// view model of a sub state, use the state's projected value:
///
///     $state.subState.viewModel(SubModel())
@propertyWrapper
public struct Model<VM: ViewModel>: DynamicProperty {
    @Environment(\.modelEnvironments) private var modelEnvironments
    @StateObject private var shared = Shared()
    
    public init(wrappedValue: VM) {
        self.wrappedValue = wrappedValue
        checkedContext()
    }

    public var wrappedValue: VM {
        didSet { checkedContext() }
    }
    
    public func update() {
        guard shared.cancellable == nil else { return }
        
        let context = checkedContext()
        context.viewEnvironments = modelEnvironments
        wrappedValue.retain()
        shared.context?.releaseFromView()
        shared.context = context
        shared.cancellable = context.observedStateDidUpdate.sink { [weak shared] in
            shared?.objectWillChange.send()
        }
    }
}

private extension Model {
    final class Shared: ObservableObject {
        var cancellable: AnyCancellable?
        var context: Context<VM.State>?

        deinit {
            context?.releaseFromView()
        }
    }
    
    @discardableResult
    func checkedContext() -> Context<VM.State> {
        guard let context = wrappedValue.rawStore else {
            fatalError("ViewModel \(type(of: wrappedValue)) must created using `viewModel()` helper")
        }
        return context
    }
}
