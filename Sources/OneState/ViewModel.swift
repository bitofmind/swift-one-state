import Foundation
import Combine

@dynamicMemberLookup
public protocol ViewModel: StoreViewProvider {
    associatedtype State
    
    func onAppear() async
}

public extension ViewModel {
    func onAppear() async {}
}

public extension ViewModel {
    var storeView: StoreView<State, State> {
        .init(context: context, path: \.self, access: .fromView)
    }
}

public extension ViewModel where State: Identifiable {
    var id: State.ID {
        let view = storeView
        return view.context[keyPath: view.path(\.id), access: view.access]
    }
}

public extension Cancellable {
    func store<VM: ViewModel>(in viewModel: VM) {
        store(in: &viewModel.context.anyCancellables)
    }
}

public extension ViewModel {
    @discardableResult func onDisappear(_ perform: @escaping () -> Void) -> AnyCancellable {
        let cancellable = AnyCancellable(perform)
        cancellable.store(in: self)
        return cancellable
    }

    @discardableResult func task(@_implicitSelfCapture _ operation: @escaping @MainActor @Sendable () async throws -> Void, `catch`: ((Error) -> Void)? = nil) -> AnyCancellable {
        let task = Task {
            do {
                try await context {
                    guard !Task.isCancelled else { return }
                    try await operation()
                }
            } catch {
                `catch`?(error)
            }
        }
        
        return onDisappear(task.cancel)
    }

    @discardableResult func onReceive<P: Publisher>(_ publisher: P, @_implicitSelfCapture perform: @escaping @MainActor @Sendable (P.Output) -> Void) -> AnyCancellable where P.Failure == Never {
        let cancellable = publisher.sink(receiveValue: { value in
            Task {
                await context {
                    perform(value)
                }
            }
        })
        cancellable.store(in: self)
        return cancellable
    }

    @discardableResult func forEach<S: AsyncSequence>(_ sequence: S,  @_implicitSelfCapture perform: @escaping @MainActor @Sendable (S.Element) async throws -> Void, `catch`: ((Error) -> Void)? = nil) -> AnyCancellable {
        task({
            for try await value in sequence {
                try await perform(value)
            }
        }, catch: `catch`)
    }

    @available(iOS 15, macOS 12,  *)
    func waitUntil(_ predicate: @autoclosure @escaping () -> Bool) async {
        _ = await context.stateDidUpdate.values.first { _ in
            await context { predicate() }
        }
    }
    
    @discardableResult func onChange<T: Equatable>(of keyPath: KeyPath<State, T>, @_implicitSelfCapture perform: @escaping (T) -> Void) -> AnyCancellable {
        onReceive(stateDidUpdatePublisher) { change in
            guard let value = change[dynamicMember: keyPath] else { return }
            perform(value)
        }
    }
    
    @discardableResult func onChange<T: Equatable>(of keyPath: KeyPath<State, T>, to value: T, @_implicitSelfCapture perform: @escaping () -> Void) -> AnyCancellable {
        onReceive(stateDidUpdatePublisher) { change in
            guard let val = change[dynamicMember: keyPath], val == value else { return }
            perform()
        }
    }

    @discardableResult func onChange<T: Equatable>(ofUnwrapped keyPath: KeyPath<State, T?>, @_implicitSelfCapture perform: @escaping (T) -> Void) -> AnyCancellable {
        onReceive(stateDidUpdatePublisher) { update in
            guard let value = update[dynamicMember: keyPath],
                let unwrapped = value else { return }
            perform(unwrapped)
        }
    }
}

extension ViewModel {
    var context: Context<State> {
        guard let context = rawStore else {
            fatalError("ViewModel \(type(of: self)) is used before fully initialized")
        }
        
        return context
    }
    
    var rawStore: Context<State>? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if let state = child.value as? ModelState<State> {
                return state.context
            }
        }
        
        return nil
    }
    
    @discardableResult func context<T>(@_inheritActorContext _ operation: @escaping @MainActor @Sendable () async throws -> T) async rethrows -> T {
        try await StoreAccess.$viewModel.withValue(.fromViewModel) {
            try await operation()
        }
    }
}

extension StoreAccess {
    @TaskLocal static var viewModel: StoreAccess?
}
