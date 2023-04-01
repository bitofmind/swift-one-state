import SwiftUI
import OneState
import OneStateTimeTraveler
import XCTestDynamicOverlay

@main
struct CounterFactApp: App {
    let store = Store<AppModel>(initialState: .init())

    var body: some Scene {
        WindowGroup {
            NavigationView {
#if os(macOS)
                EmptyView()
#endif
                if !_XCTIsTesting {
                    AppView(model: store.model)
                }
            }
#if !os(macOS)
            .navigationViewStyle(.stack)
#endif
            .advertise(store)
        }
    }
}
