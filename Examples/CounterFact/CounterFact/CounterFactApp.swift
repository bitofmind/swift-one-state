import SwiftUI
import OneState
import OneStateTimeTraveler

@main
struct CounterFactApp: App {
    let store = Store<AppModel>(initialState: .init())

    var body: some Scene {
        WindowGroup {
            NavigationView {
#if os(macOS)
                EmptyView()
#endif
                AppView(model: store.model)
            }
#if !os(macOS)
            .navigationViewStyle(.stack)
#endif
            .advertise(store)
        }
    }
}
