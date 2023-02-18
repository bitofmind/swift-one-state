#if canImport(SwiftUI)
import SwiftUI
import CustomDump

@propertyWrapper
@dynamicMemberLookup
/// Declares a model that will invalidates a view whenever any observed state changes.
///
///   struct MyView: View {
///     @ObservedModel var model: MyModel
///
///     var body: some View {
///       Button("Log in \(model.userName)") {
///         model.loginButtonTapped()
///       }
///     }
///   }
public struct ObservedModel<M: ModelContainer>: DynamicProperty {
    @StateObject var access = ViewAccess()

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
        let hasBeenRemoved = wrappedValue.models.reduce(false) { $0 || $1.context.hasBeenRemoved }
        guard !hasBeenRemoved else { return }

        wrappedValue = M.modelContainer(from: wrappedValue.models.map { model in
            StoreAccess.with(access) {
                M.ModelElement(context: model.context)
            }
        })
    }
}

extension ObservedModel: StoreViewProvider where M: Model {
    public var storeView: StoreView<M.State, M.State, Write> {
        wrappedValue.storeView
    }
}

public extension View {
    @MainActor
    func printObservedUpdates<M: Model>(for observedModel: ObservedModel<M>) -> some View {
        modifier(PrintObservedUpdatesModifier(model: observedModel.wrappedValue, updateCount: observedModel.access.updateCount))
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

private struct PrintObservedUpdatesModifier<M: Model>: ViewModifier {
    var model: M
    let updateCount: Int
    @State var last: M.State?

    func body(content: Content) -> some View {
        content
            .onAppear {
                self.last = model.nonObservableState
            }
            .onChange(of: updateCount) { updateCount in
                let current = model.nonObservableState
                if let last {
                    if let diff = CustomDump.diff(last, current) {
                        print("Observed update for \(type(of: model)):\n", diff)
                    }
                }
                self.last = current
            }
    }
}

#endif
