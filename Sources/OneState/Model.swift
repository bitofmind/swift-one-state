import SwiftUI

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
@dynamicMemberLookup
public struct Model<VM: ViewModel>: DynamicProperty {
    @Environment(\.modelEnvironments) private var modelEnvironments
    @StateObject private var access = ModelAccess<VM.State>()

    public init(wrappedValue: VM) {
        self.wrappedValue = wrappedValue
        checkedContext()
    }

    public var wrappedValue: VM {
        didSet { checkedContext() }
    }

    public var projectedValue: Self {
        self
    }

    public mutating func update() {
        let context = checkedContext()
        let prevContext = access.context
        access.context = context
        if wrappedValue.modelState?.storeAccess !== access {
            StoreAccess.$current.withValue(access) {
                context.propertyIndex = 0
                ContextBase.$current.withValue(context) {
                    wrappedValue = VM()
                }
            }
        }

        guard context !== prevContext else { return }

        prevContext?.releaseFromView()
        context.viewEnvironments = modelEnvironments
        wrappedValue.retain()
        access.startObserve()
    }
}

extension Model: StoreViewProvider {
    public var storeView: StoreView<VM.State, VM.State, Write> {
        wrappedValue.storeView
    }
}

private extension Model {
    @discardableResult
    func checkedContext() -> Context<VM.State> {
        guard let context = wrappedValue.modelState?.context as? Context<VM.State> else {
            fatalError("ViewModel \(type(of: wrappedValue)) must be created via a @StateModel or the provide initializer taking a ViewStore. This is required for the view models state to be hooked up to view into a store.")
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
