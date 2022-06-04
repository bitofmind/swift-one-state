import Foundation

#if canImport(Combine)
import Combine

public extension ViewModel {
    /// Receive updates from a publisher for the life time of the model
    ///
    /// - Parameter catch: Called if the sequence throws an error
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult @MainActor
    func onReceive<P: Publisher>(_ publisher: P, perform: @escaping @MainActor (P.Output) -> Void, `catch`: (@MainActor (Error) -> Void)? = nil) -> Cancellable {
        let cancellable = publisher.sink(receiveCompletion: { completion in
            if case let .failure(error) = completion {
                `catch`?(error)
            }
        }, receiveValue: { value in
            perform(value)
        })

        cancellable.store(in: self)
        return cancellable
    }
}

public extension StoreViewProvider {
    var stateUpdatePublisher: AnyPublisher<StateUpdate<State>, Never> {
        PassthroughSubject(stateUpdates).eraseToAnyPublisher()
    }
}

public extension StoreViewProvider where State: Equatable {
    var valuePublisher: AnyPublisher<State, Never> {
        PassthroughSubject(values).eraseToAnyPublisher()
    }
}

extension ModelProperty: Publisher {
    public typealias Output = Value
    public typealias Failure = Never

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == Value, S.Failure == Never {
        PassthroughSubject(self).receive(subscriber: subscriber)
    }
}

extension StateView: Publisher where Value: Equatable {
    public typealias Output = Value
    public typealias Failure = Never

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == Value, S.Failure == Never {
        PassthroughSubject(self).receive(subscriber: subscriber)
    }
}

extension PassthroughSubject where Failure == Never {
    convenience init<T: AsyncSequence>(_ sequence: T) where T.Element == Output {
        self.init()

        Task {
            for try await value in sequence {
                self.send(value)
            }

            self.send(completion: .finished)
        }
    }
}

extension Combine.AnyCancellable: Cancellable {}

extension Store: ObservableObject {}

#endif
