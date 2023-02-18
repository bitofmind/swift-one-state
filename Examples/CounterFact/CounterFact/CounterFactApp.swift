import SwiftUI
import OneState

@main
struct CounterFactApp: App {
    let store = Store<AppModel>(initialState: .init())

    var body: some Scene {
        WindowGroup {
            NavigationView {
                AppView(model: store.model)
            }
        }
    }
}
