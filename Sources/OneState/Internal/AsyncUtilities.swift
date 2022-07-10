import Foundation

final class AsyncPassthroughSubject<Element>: AsyncSequence, @unchecked Sendable {
    var lock = Lock()
    var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]

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
            let key = UUID()
            continuation.onTermination = { @Sendable _ in
                self.lock {
                    self.continuations[key] = nil
                }
            }

            lock {
                continuations[key] = continuation
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

#if swift(<5.7)
extension AsyncStream: @unchecked Sendable where Element: Sendable {}
#endif

extension AnyKeyPath: @unchecked Sendable {}
