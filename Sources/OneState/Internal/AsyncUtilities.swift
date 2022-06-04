import Foundation

final class AsyncPassthroughSubject<Element>: AsyncSequence {
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
    init<S: AsyncSequence>(_ sequence: S) rethrows where S.Element == Element {
        self.init { c in
            let task = Task {
                for try await element in sequence {
                    c.yield(element)
                }

                c.finish()
            }

            c.onTermination = { @Sendable _ in task.cancel() }
        }
    }
}
