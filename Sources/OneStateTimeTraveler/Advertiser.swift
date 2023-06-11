import Foundation
import OneState
import Network
import SwiftUI

@available(iOS 15.0, macOS 12.0, tvOS 15.0, watchOS 8.0, *)
public extension View {
    func advertise(_ advertiser: Advertiser) -> some View {
        task {
            try? await advertiser.advertise()
        }
    }
    
    func advertise<Models: ModelContainer>(_ store: Store<Models>, reducer: StateHistoryReducer<Models.StateContainer> = .default, discoveryInfo: [String: String] = .discoveryInfo, onConnect: @escaping (Data?) -> Bool = { _ in true }) -> some View {
        advertise(.store(store, reducer: reducer, discoveryInfo: discoveryInfo, onConnect: onConnect))
    }
}

public struct Advertiser {
    public var traveler: TimeTraveler
    public var discoveryInfo: [String: String] = .discoveryInfo
    public var onConnect: (Data?) -> Bool
    
    public init(traveler: TimeTraveler, discoveryInfo: [String: String] = .discoveryInfo, onConnect: @escaping (Data?) -> Bool = { _ in true }) {
        self.traveler = traveler
        self.discoveryInfo = discoveryInfo
        self.onConnect = onConnect
    }
}

public extension Advertiser {
    static func store<Models: ModelContainer>(_ store: Store<Models>, reducer: StateHistoryReducer<Models.StateContainer> = .default, discoveryInfo: [String: String] = .discoveryInfo, onConnect: @escaping (Data?) -> Bool = { _ in true }) -> Self {
        Self(traveler: .local(for: store), discoveryInfo: discoveryInfo, onConnect: onConnect)
    }
}

public extension Advertiser {
    func advertise() async throws {
        let udpOption = NWProtocolUDP.Options()
        let params = NWParameters(dtls: nil, udp: udpOption)
        params.includePeerToPeer = true

        let listener = try NWListener(using: params)
        listener.service = NWListener.Service(name: "OneStateTimeTraveler", type: "_onestatetimetraveler._udp", txtRecord: .init(.discoveryInfo))
        
        let tasks = Protected<[Task<(), Error>]>([])
        listener.newConnectionHandler = { newConnection in
            tasks.value.forEach { $0.cancel() }
            tasks.value.removeAll()

            tasks.value.append(Task {
                for await state in traveler.stateStream() {
                    try await newConnection.send(AdvertiserMessage.overrideState(state))
                }
            })
            
            tasks.value.append(Task {
                while !Task.isCancelled {
                    let command = try await newConnection.receiveMessage(ofType: BrowserMessage.self)
                    
                    switch command {
                    case .onConnect:
                        break
                    
                    case let .setOverride(index: index):
                        traveler.setOverride(index)
                    
                    case let .printDiff(index: index):
                        traveler.printDiff(index)
                    }
                }
            })
            
            newConnection.start(queue: .main)
        }
        
        let task = Protected<Task<Void, Error>?>(nil)
        listener.stateUpdateHandler = { [weak listener] state in
            switch state {
            case .failed:
                listener?.cancel()
                task.value = Task {
                    try await advertise()
                }
            default:
                break
            }
        }
        
        listener.start(queue: .main)
        
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: NSEC_PER_SEC * 1_0000_0000)
        }
          
        task.value?.cancel()
        _ = listener
    }
}

enum AdvertiserMessage: Equatable, Sendable, Codable {
    case overrideState(OverrideState?)
}

public extension [String: String] {
    static let discoveryInfo: Self = [
        "globallyUniqueString": ProcessInfo.processInfo.globallyUniqueString,
        "hostName": deviceName,
        "processName": ProcessInfo.processInfo.processName,
        "platform": platform + (isSimulator ? " Simulator" : ""),
    ]
}

var deviceName: String {
#if os(iOS)
    UIDevice.current.name
#else
    ProcessInfo.processInfo.hostName
#endif
}

var isSimulator: Bool {
#if targetEnvironment(simulator)
    true
#else
    false
#endif
}
    
var platform: String {
#if os(iOS)
    "iOS"
#elseif os(watchOS)
    "watchOS"
#elseif os(tvOS)
    "tvOS"
#elseif os(macOS)
    "macOS"
#else
    "unknown"
#endif
}
