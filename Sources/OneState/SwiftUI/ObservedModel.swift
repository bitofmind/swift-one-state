#if canImport(SwiftUI)
import SwiftUI

@propertyWrapper
@dynamicMemberLookup
public struct ObservedModel<M: Model>: DynamicProperty {
    @StateObject private var access = ModelAccess<M.State>()

    public init(wrappedValue: M) {
        self.wrappedValue = wrappedValue
        checkedContext()
    }

    public var wrappedValue: M {
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
                wrappedValue = M(context: context)
            }
        }

        guard context !== prevContext else { return }

        prevContext?.releaseFromView()
        wrappedValue.retain()
        access.startObserve()
    }
}

extension ObservedModel: StoreViewProvider {
    public var storeView: StoreView<M.State, M.State, Write> {
        wrappedValue.storeView
    }
}

private extension ObservedModel {
    @discardableResult
    func checkedContext() -> Context<M.State> {
        guard let context = wrappedValue.modelState?.context as? Context<M.State> else {
            fatalError("Model \(type(of: wrappedValue)) must be created via a @StateModel or the provide initializer taking a ViewStore. This is required for the view models state to be hooked up to view into a store.")
        }
        return context
    }
}

public struct UsingModel<M: Model, Content: View>: View {
    @ObservedModel var model: M
    var content: (M) -> Content

    public init(_ model: M, @ViewBuilder content: @escaping (M) -> Content) {
        self.model = model
        self.content = content
    }

    public var body: some View {
        content(model)
    }
}

#endif
