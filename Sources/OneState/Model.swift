import SwiftUI
import Combine

/// Declares a view models state
///
/// A model conforming to `ViewModel` must declare its state  using `@ModelState` where
/// the type is matching its associatedtype `State`.
///
///     struct MyModel: ViewModel {
///         @ModelState private var state: State
///     }
///
/// You then can create an instance by providing a store or a view into a store:
///
///     let model = MyModel($store)
///
///     let subModel = SubModel(model.sub)
///
/// Or by declaring you sub state using `@ModelState`:
///
///     let subModel = model.$sub
///
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

public struct UsingModel<VM: ViewModel, Content: View>: View {
    @Model var model: VM
    var content: (VM) -> Content

    public init(_ model: VM, @ViewBuilder content: @escaping (VM) -> Content) {
        self.model = model
        self.content = content
    }

    public var body: some View {
        content(model)
    }
}
