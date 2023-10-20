import Foundation

final class AsyncPassthroughSubject<Element>: AsyncSequence, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [Int: AsyncStream<Element>.Continuation] = [:]
    private var nextKey = 0

    init() {}

    func yield(_ element: Element) {
        let conts = lock { continuations.values }
        for cont in conts {
            cont.yield(element)
        }
    }

    func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        AsyncStream(Element.self) { continuation in
            let key: Int = lock {
                nextKey += 1;
                continuations[nextKey] = continuation
                return nextKey
            }

            continuation.onTermination = { @Sendable _ in
                self.lock {
                    self.continuations[key] = nil
                }
            }
        }.makeAsyncIterator()
    }
}

public struct AnyAsyncIterator<Element>: AsyncIteratorProtocol {
    let nextClosure: () async -> Element?

    init<T: AsyncIteratorProtocol>(_ iterator: T) where T.Element == Element {
        var iterator = iterator
        nextClosure = { try? await iterator.next() }
    }

    public func next() async -> Element? {
        await nextClosure()
    }
}

extension AnyAsyncIterator: @unchecked Sendable where Element: Sendable {}

public struct AnyAsyncSequence<Element>: AsyncSequence {
    let makeAsyncIteratorClosure: () -> AsyncIterator

    public init<T: AsyncSequence>(_ sequence: T) where T.Element == Element {
        makeAsyncIteratorClosure = { AnyAsyncIterator(sequence.makeAsyncIterator()) }
    }

    public func makeAsyncIterator() -> AnyAsyncIterator<Element> {
        AnyAsyncIterator(makeAsyncIteratorClosure())
    }
}

extension AnyAsyncSequence: @unchecked Sendable where Element: Sendable {}

struct CallContextsIterator<Element>: AsyncIteratorProtocol {
    let nextClosure: () async -> WithCallContexts<Element>?

    init<T: AsyncIteratorProtocol>(_ iterator: T) where T.Element == WithCallContexts<Element> {
        var iterator = iterator
        nextClosure = { try? await iterator.next() }
    }

    func next() async -> Element? {
        let value = await nextClosure()
        CallContext.streamContexts.value = value?.callContexts ?? []
        return value?.value
    }
}

extension CallContextsIterator: @unchecked Sendable where Element: Sendable {}

struct CallContextsStream<Element>: AsyncSequence {
    let makeAsyncIteratorClosure: () -> CallContextsIterator<Element>

    init<S: AsyncSequence>(_ sequence: S) where S.Element == WithCallContexts<Element> {
        makeAsyncIteratorClosure = { CallContextsIterator(sequence.makeAsyncIterator()) }
    }

    func makeAsyncIterator() -> CallContextsIterator<Element> {
        makeAsyncIteratorClosure()
    }
}

extension CallContextsStream: @unchecked Sendable where Element: Sendable {}

#if swift(<5.7)
extension AsyncStream: @unchecked Sendable where Element: Sendable {}
#endif

extension AnyKeyPath: @unchecked Sendable {}
