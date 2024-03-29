import Foundation

#if canImport(Combine)
@preconcurrency import Combine

public extension Model {
    /// Receive updates from a publisher for the life time of the model
    ///
    /// - Parameter catch: Called if the sequence throws an error
    /// - Returns: A cancellable to optionally allow cancelling before a view goes away
    @discardableResult
    func onReceive<P: Publisher>(_ publisher: P, perform: @escaping (P.Output) -> Void, `catch`: ((Error) -> Void)? = nil) -> Cancellable {
        let cancellable = publisher.sink(receiveCompletion: { completion in
            if case let .failure(error) = completion {
                `catch`?(error)
            }
        }, receiveValue: { value in
            perform(value)
        })

        return onCancel {
            cancellable.cancel()
        }
    }
}

public extension StoreViewProvider where State: Sendable {
    var stateDidUpdatePublisher: AnyPublisher<(), Never> {
        let stateDidUpdate = stateDidUpdate
        return PassthroughSubject(stateDidUpdate).eraseToAnyPublisher()
    }
}

public extension StoreViewProvider where State: Equatable&Sendable {
    var changesPublisher: AnyPublisher<State, Never> {
        PassthroughSubject(changes).eraseToAnyPublisher()
    }

    var valuesPublisher: AnyPublisher<State, Never> {
        PassthroughSubject(values).eraseToAnyPublisher()
    }
}

extension ModelProperty: Publisher {
    public typealias Output = Value
    public typealias Failure = Never

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == Value, S.Failure == Never, Value: Sendable {
        PassthroughSubject(self).receive(subscriber: subscriber)
    }
}

extension StateView: Publisher where Value: Equatable {
    public typealias Output = Value
    public typealias Failure = Never

    public func receive<S>(subscriber: S) where S : Subscriber, S.Input == Value, S.Failure == Never, Value: Sendable {
        PassthroughSubject(self).receive(subscriber: subscriber)
    }
}

extension PassthroughSubject where Failure == Never, Output: Sendable {
    convenience init<S: AsyncSequence&Sendable>(_ sequence: S) where S.Element == Output {
        self.init()

        Task {
            for try await value in sequence {
                self.send(value)
            }

            self.send(completion: .finished)
        }
    }
}

extension PassthroughSubject: @unchecked Sendable where Output: Sendable {}

#endif
