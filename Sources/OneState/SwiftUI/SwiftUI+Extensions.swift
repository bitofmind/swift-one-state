#if canImport(SwiftUI)
import SwiftUI

public extension Binding where Value: Equatable {
    init(_ modelState: ModelState<Value>) {
        self.init(
            get: { modelState.context.value(for: \.self, access: modelState.storeAccess) },
            set: { modelState.wrappedValue = $0 }
        )
    }
}

public extension ViewModel {
    subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, Writable<T>>) -> Binding<T> {
        let storeView = self.storeView
        return .init {
            storeView.value(for: keyPath).wrappedValue
        } set: { newValue in
            storeView.setValue(newValue, at: keyPath)
        }
    }

    @MainActor
    subscript<VM: ViewModel>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<VM>>>) -> Binding<VM> where VM.StateContainer == VM.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            setValue(StateModel<VM>(wrappedValue: models.stateContainer), at: path)
        }
    }


    @MainActor
    subscript<Models>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<Models>>>) -> Binding<Models> where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            let stateModel = StateModel<Models>(wrappedValue: models.stateContainer)
            setValue(stateModel, at: path)
        }
    }
}

public extension ViewModel {
    func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
        let callContext = CallContext { action in
            SwiftUI.withAnimation(animation) {
                action()
            }
        }

        return try CallContext.$current.withValue(callContext) {
            try body()
        }
    }
}

public extension StoreViewProvider where Access == Write {
    subscript<T>(dynamicMember path: WritableKeyPath<State, Writable<T?>>) -> Binding<StoreView<Root, T, Write>?> {
        let view = self.storeView
        return .init {
            view.storeView(for: path.appending(path: \.wrappedValue))
        } set: { newValue in
            view.setValue(newValue.map {
                $0.context[path: $0.path, access: view.access]
            }, at: path)
        }
    }
}

#endif
