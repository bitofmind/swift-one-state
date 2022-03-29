import SwiftUI
import Combine

@propertyWrapper
public struct Model<VM: ViewModel>: DynamicProperty {
    @Environment(\.modelEnvironments) private var modelEnvironments
    @StateObject private var shared = Shared()
    
    public init(wrappedValue: VM) {
        self.wrappedValue = wrappedValue
    }

    public var wrappedValue: VM
    
    public func update() {
        guard shared.cancellable == nil else { return }
        
        guard let context = wrappedValue.rawStore else {
            fatalError("ViewModel \(type(of: wrappedValue)) must created using `viewModel()` helper")
        }
        
        if !context.isOverrideStore && !context.isFullyInitialized {
            context.environments = modelEnvironments
            context.isFullyInitialized = true
            
            Task {
                await StoreAccess.$viewModel.withValue(.fromViewModel) { @MainActor in
                    await wrappedValue.onAppear()
                }
            }
        }
        
        shared.context = context
        shared.cancellable = context.observedStateDidUpdate.sink { [weak shared] in
            shared?.objectWillChange.send()
        }
    }
}

private extension Model {
    final class Shared: ObservableObject {
        var cancellable: AnyCancellable?
        var context: Context<VM.State>! {
            willSet {
                context?.releaseFromView()
                newValue.retainFromView()
            }
        }

        deinit {
            context.releaseFromView()
        }
    }
}

public extension StoreViewProvider {
    func viewModel<VM: ViewModel>(_ viewModel: @escaping @autoclosure () -> VM) -> VM where VM.State == State {
        let view = storeView
        let context = view.context.context(at: view.path)

        context.propertyIndex = 0
        return ContextBase.$current.withValue(context) {
             viewModel()
        }
    }
}
