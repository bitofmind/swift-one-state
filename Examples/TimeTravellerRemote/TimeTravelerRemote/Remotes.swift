import Foundation
import OneState
import OneStateExtensions
import OneStateTimeTraveler
import IdentifiedCollections
import SwiftUI

struct RemotesModel: Model {
    struct State {
        @StateModel<IdentifiedArrayOf<RemoteModel>> var remotes = []
    }
    
    @ModelState var state: State
    
    func onActivate() {
        forEach(browse()) { travelers in
            let oldRemotes = state.remotes
            state.remotes = .init(uniqueElements: travelers.map {
                oldRemotes[id: $0.info] ?? .init(info: $0.info)
            })
            
            struct ID {}
            cancelAll(for: ID.self)
            
            withCancellationContext(ID.self) {
                for (info, traveler) in travelers {
                    forEach(traveler.stateStream()) { overrideState in
                        state.remotes[id: info]?.overrideState = overrideState
                    }
                    
                    forEach(events(from: \.$remotes)) { event, remote in
                        guard remote.info == info else { return }
                        switch event {
                        case let .setOverride(index):
                            traveler.setOverride(index)
                        case let .printDiff(index):
                            traveler.printDiff(index)
                        }
                    }
                }
            }
         }
    }
}

struct RemotesView: View {
    @ObservedModel var model: RemotesModel
    
    var body: some View {
        if model.$remotes.isEmpty {
            Text("Searching for time travelers...")
                .padding()
        } else {
            ForEach(model.$remotes) { remote in
                RemoteView(model: remote)
                
                Divider()
            }
            .padding(.bottom, -1)
        }
    }
}
