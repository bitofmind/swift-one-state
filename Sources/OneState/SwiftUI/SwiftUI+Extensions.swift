#if canImport(SwiftUI)
import SwiftUI
import CustomDump

public extension Binding where Value: Equatable {
    init(_ modelState: ModelState<Value>) {
        self.init(
            get: { modelState.context.value(for: \.self, access: modelState.storeAccess) },
            set: { modelState.wrappedValue = $0 }
        )
    }
}

public extension Model {
    subscript<T: Equatable>(dynamicMember keyPath: WritableKeyPath<State, Writable<T>>) -> Binding<T> {
        let storeView = self.storeView
        return .init {
            storeView.value(for: keyPath).wrappedValue
        } set: { newValue in
            storeView.setValue(newValue, at: keyPath)
        }
    }

    subscript<M: Model>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<M>>>) -> Binding<M> where M.StateContainer == M.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            setValue(StateModel<M>(wrappedValue: models.stateContainer), at: path)
        }
    }

    subscript<Models>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<Models>>>) -> Binding<Models> where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            let stateModel = StateModel<Models>(wrappedValue: models.stateContainer)
            setValue(stateModel, at: path)
        }
    }
}

@discardableResult
public func withAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    try withCallContext(body: body) { action in
        SwiftUI.withAnimation(animation) {
            action()
        }
    }
}

@discardableResult
public func withTransaction<Result>(_ transaction: Transaction, _ body: () throws -> Result) rethrows -> Result {
    try withCallContext(body: body) { action in
         SwiftUI.withTransaction(transaction) {
             action()
         }
     }
}

public extension StoreViewProvider where Access == Write {
    subscript<T>(dynamicMember path: WritableKeyPath<State, Writable<T?>>) -> Binding<StoreView<Root, T?, Write>> {
        let view = self.storeView
        return .init {
            view.storeView(for: path.appending(path: \.wrappedValue))
        } set: { newValue in
            view.setValue(newValue.nonObservableState, at: path)
        }
    }
}

public extension View {
    @available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
    func printStateUpdates<P: StoreViewProvider>(for provider: P, name: String = "") -> some View where P.State: Sendable {
        task {
            var previous = provider.nonObservableState
            for await _ in provider.stateDidUpdate {
                let state = provider.nonObservableState
                guard let diff = diff(previous, state) else { return }
                previous = state
                print("State did update\(name.isEmpty ? "" : " for \(name)"):\n" + diff)
            }
        }
    }
}

#endif
