#if canImport(SwiftUI)
import SwiftUI

@propertyWrapper
@dynamicMemberLookup
public struct ObservedModel<M: ModelContainer>: DynamicProperty {
    @StateObject private var access = ViewAccess()

    public init(wrappedValue: M) {
        self.wrappedValue = wrappedValue
        wrappedValue.checkedContexts()
    }

    public var wrappedValue: M {
        didSet { wrappedValue.checkedContexts() }
    }

    public var projectedValue: Self {
        self
    }

    public mutating func update() {
        let contexts = wrappedValue.checkedContexts()
        let prevContexts = access.contexts

        wrappedValue = M.modelContainer(from: wrappedValue.models.compactMap { model in
            StoreAccess.$current.withValue(Weak(value: access)) {
                M.ModelElement(context: model.context)
            }
        })

        guard !contexts.elementsEqual(prevContexts, by: ===) else { return }

        prevContexts.forEach { $0.activationRelease() }
        wrappedValue.models.forEach { $0.retain() }
        access.startObserving(from: contexts)
        access.objectWillChange.send()
    }
}

extension ObservedModel: StoreViewProvider where M: Model {
    public var storeView: StoreView<M.State, M.State, Write> {
        wrappedValue.storeView
    }
}

public struct UsingModel<M: ModelContainer, Content: View>: View {
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

private extension ModelContainer {
    @discardableResult
    func checkedContexts() -> [Context<ModelElement.State>] {
        models.map { model in
            guard let context = model.modelState?.context as? Context<ModelElement.State> else {
                fatalError("Model \(type(of: self)) must be created via a @StateModel or the provide initializer taking a ViewStore. This is required for the view models state to be hooked up to view into a store.")
            }
            return context
        }
    }
}

#endif
