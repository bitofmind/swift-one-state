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

#if swift(<5.7)
extension AsyncStream: @unchecked Sendable where Element: Sendable {}
#endif

extension AnyKeyPath: @unchecked Sendable {}
