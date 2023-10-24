import Foundation

final class AsyncPassthroughSubject<Element>: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private var continuations: [Int: AsyncStream<Element>.Continuation] = [:]
    private var nextKey = 0

    init() {}

    func yield(_ element: Element) {
        let conts = lock { continuations.values }
        for cont in conts {
            cont.yield(element)
        }
    }

    func stream() -> AsyncStream<Element> {
        lock {
            let (stream, cont) = AsyncStream<Element>.makeStream()
            nextKey += 1;
            let key = nextKey

            continuations[key] = cont
            cont.onTermination = { @Sendable _ in
                self.lock {
                    self.continuations[key] = nil
                }
            }

            return stream
        }
    }
}

#if swift(<5.7)
extension AsyncStream: @unchecked Sendable where Element: Sendable {}
#endif

extension AnyKeyPath: @unchecked Sendable {}
