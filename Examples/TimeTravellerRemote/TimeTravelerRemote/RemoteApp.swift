import SwiftUI
import OneState

@main
struct RemoteApp: App {
    let store = Store<RemotesModel>(initialState: .init())
    
    var body: some Scene {
        MenuBarExtra {
            RemotesView(model: store.model)
        } label: {
            Image(systemName: "playpause.circle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
