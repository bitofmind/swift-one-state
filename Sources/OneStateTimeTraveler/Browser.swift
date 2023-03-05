import Foundation
import Network
import OrderedCollections
import AsyncAlgorithms

public func browse() -> AsyncStream<[(info: [String: String], traveler: TimeTraveler)]> {
    AsyncStream { continuation in
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_onestatetimetraveler._udp", domain: "local"), using: params)
        
        var travelers: OrderedDictionary<[String: String], (traveler: TimeTraveler, connection: NWConnection)> = [:]
        func yield() {
            continuation.yield(travelers.filter { !$0.key.isEmpty }.map { ($0.key, $0.value.traveler) })
        }

        browser.stateUpdateHandler = { _ in }
        
        browser.browseResultsChangedHandler = { results, changes in
            for change in changes {
                switch change {
                case let .added(result), let .changed(old: _, new: result, flags: _):
                    
                    let udpOption = NWProtocolUDP.Options()
                    let params = NWParameters(dtls: nil, udp: udpOption)
                    params.includePeerToPeer = true
                    let connection = NWConnection(to: result.endpoint, using: params)
                    
                    
                    let stateStream = AsyncChannel<OverrideState?>()
                    Task {
                        while !Task.isCancelled {
                            let message = try await connection.receiveMessage(ofType: AdvertiserMessage.self)
                            switch message {
                            case let .overrideState(state):
                                await stateStream.send(state)
                            }
                        }
                    }
                    
                    let traveler = TimeTraveler(
                        stateStream: { AsyncStream(stateStream) },
                        setOverride: { index in
                            Task {
                                try await connection.send(BrowserMessage.setOverride(index: index))
                            }
                        },
                        printDiff: { index in
                            Task {
                                try await connection.send(BrowserMessage.printDiff(index: index))
                            }
                        }
                    )
                    
                    travelers[result.metadata.info] = (traveler, connection)
                    connection.start(queue: .main)
                    
                    yield()
                    
                    Task {
                        try await connection.send(BrowserMessage.onConnect)
                    }
                    
                default:
                    break
                }
                
                switch change {
                case let .changed(old: old, new: new, flags: _) where old.metadata.info != new.metadata.info:
                    travelers[old.metadata.info] = nil
                    yield()

                case let .removed(result):
                    travelers[result.metadata.info] = nil
                    yield()

                default:
                    break
                }
            }
        }
        
        browser.start(queue: .main)
    }
}

enum BrowserMessage: Equatable, Codable, Sendable {
    case onConnect
    case setOverride(index: Int?)
    case printDiff(index: Int)
}

extension NWBrowser.Result.Metadata {
    var info: [String: String] {
        switch self {
        case let .bonjour(record):
            return record.dictionary
        default:
            return [:]
        }
    }
}

extension NWConnection {
    func send<T: Encodable>(_ value: T) async throws {
        try await withCheckedThrowingContinuation { continuation in
            do {
                //print("Will send", value)
                let data = try JSONEncoder().encode(value)
                self.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                })
            } catch {
                continuation.resume(throwing: error)
            }
        } as Void
    }
    
    func receiveMessage<T: Decodable>(ofType type: T.Type = T.self) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            self.receiveMessage { data, context, isComplete, error in
                do {
                    switch (data, error) {
                    case let (data?, nil):
                        let value = try JSONDecoder().decode(T.self, from: data)
                        //print("Did receive", value)
                        continuation.resume(returning: value)
                    case let (_, error?):
                        throw error
                    case (nil, nil):
                        throw URLError(.cancelled)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
