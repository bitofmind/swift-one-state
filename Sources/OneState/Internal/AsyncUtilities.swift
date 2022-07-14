import Foundation

final class AsyncPassthroughSubject<Element>: AsyncSequence, @unchecked Sendable {
    private var lock = Lock()
    private var continuations: [Int: AsyncStream<Element>.Continuation] = [:]
    private var nextKey = 0

    init() {}

    func yield(_ element: Element) {
        lock {
            for cont in continuations.values {
                cont.yield(element)
            }
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

extension AsyncStream {
    init<S: AsyncSequence>(_ sequence: @autoclosure @escaping @Sendable () -> S) rethrows where S.Element == Element {
        self.init { c in
            let task = Task {
                for try await element in sequence() {
                    c.yield(element)
                }

                c.finish()
            }

            c.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}

public final class CallContextsStream<Element>: AsyncSequence {
    let stream: AsyncStream<WithCallContexts<Element>>

    init<S: AsyncSequence>(_ sequence: @autoclosure @escaping @Sendable () -> S) rethrows where S.Element == WithCallContexts<Element> {
        stream = try! .init(sequence())
    }

    public func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
        let stream = self.stream
        return AsyncStream(stream.map(\.value)).makeAsyncIterator()
    }
}

extension CallContextsStream: @unchecked Sendable where Element: Sendable {}

#if swift(<5.7)
extension AsyncStream: @unchecked Sendable where Element: Sendable {}
#endif

extension AnyKeyPath: @unchecked Sendable {}
