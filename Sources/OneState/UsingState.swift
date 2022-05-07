import SwiftUI
import Combine

public struct UsingState<State, Content: View>: View {
    private var content: (Shared) -> Content?
    @StateObject private var shared = Shared()
    
    public var body: some View {
        if let view = content(shared) {
            view
        }
    }
}

public extension UsingState {
    init<S: StoreViewProvider>(_ provider: S?, @ViewBuilder content: @escaping (StoreView<State, State>) -> Content) where S.State == State {
        self.content = { shared in
            guard let view = provider else {
                return nil
            }
            
            return content(.init(context: shared.context(from: view), path: \.self, access: .fromView))
        }
    }
    
    init<S: StoreViewProvider>(_ provider: S, @ViewBuilder content: @escaping (StoreView<State, State>) -> Content) where S.State == State? {
        self.init(provider.storeView(for: \.self), content: content)
    }
    
    init<S: StoreViewProvider>(_ provider: S, @ViewBuilder content: @escaping (StoreView<State, State>) -> Content) where S.State == State {
        self.content = { shared in
            content(.init(context: shared.context(from: provider), path: \.self, access: .fromView))
        }
    }

    init<S: StoreViewProvider>(_ provider: S, @ViewBuilder content: @escaping (Binding<State>) -> Content) where S.State == Writable<State> {
        self.content = { shared in
            content(.init {
                shared.context(from: provider.storeView(for: \.wrappedValue)).value(for: \.self, access: .fromView)
            } set: { newValue in
                shared.context[keyPath: \.self, access: .fromView] = newValue
            })
        }
    }
    
    init<S: StoreViewProvider>(_ provider: S, @ViewBuilder content: @escaping (Binding<State>) -> Content) where S.State == Writable<State>, State: Equatable {
        self.content = { shared in
            content(.init {
                shared.context(from: provider.storeView(for: \.wrappedValue)).value(for: \.self, access: .fromView)
            } set: { newValue in
                shared.context[keyPath: \.self, access: .fromView] = newValue
            })
        }
    }

    init<S: StoreViewProvider>(_ provider: Binding<S?>, @ViewBuilder content: @escaping (Binding<State>) -> Content) where S.State == State {
        self.content = { shared in
            guard let view = provider.wrappedValue else {
                return nil
            }

            return content(.init {
                shared.context(from: view).value(for: \.self, access: .fromView)
            } set: { newValue in
                shared.context[keyPath: \.self, access: .fromView] = newValue
            })
        }
    }
    
    init<S: StoreViewProvider>(_ provider: Binding<S?>, @ViewBuilder content: @escaping (Binding<State>) -> Content) where S.State == State, State: Equatable {
        self.content = { shared in
            guard let view = provider.wrappedValue else {
                return nil
            }

            return content(.init {
                shared.context(from: view).value(for: \.self, access: .fromView)
            } set: { newValue in
                shared.context[keyPath: \.self, access: .fromView] = newValue
            })
        }
    }
}

private extension UsingState {
    final class Shared: ObservableObject {
        var anyCancelable: AnyCancellable?
        var context: Context<State>!

        func context<S: StoreViewProvider>(from view: S) -> Context<State> where S.State == State {
            if anyCancelable == nil {
                let view = view.storeView
                context = ChildContext(context: view.context, path: view.path)
                anyCancelable = context.observedStateDidUpdate.sink { [weak self] in
                    self?.objectWillChange.send()
                }
            }
            
            return context
        }
    }
}
    
