import Foundation
import SwiftUI
import OneState

struct CounterModel: Model {
    struct State: Equatable {
        @Writable var alert: Alert?
        @Writable var count = 0

        struct Alert: Equatable, Identifiable {
            var message: String
            var title: String

            var id: String { title + message }
        }
    }

    enum Event: Equatable {
        case onFact(String)
    }

    @ModelDependency(\.factClient.fetch) var fetchFact
    @ModelState private var state: State

    func decrementTapped() {
        state.count -= 1
    }

    func incrementTapped() {
        state.count += 1
    }

    func factButtonTapped() {
        task {
            send(.onFact(try await fetchFact(state.count)))
        } catch: { _ in
            state.alert = .init(message: "Couldn't load fact.", title: "Error")
        }
    }
}

struct CounterView: View {
    @ObservedModel var model: CounterModel

    var body: some View {
        VStack {
            HStack {
                Button("-") { model.decrementTapped() }
                Text("\(model.count)")
                Button("+") { model.incrementTapped() }

                Button("Fact") { model.factButtonTapped() }
            }
        }
        .alert(item: model.$alert) { alert in
          Alert(
            title: Text(alert.title),
            message: Text(alert.message)
          )
        }
    }
}

struct CounterRowModel: Model, Identifiable, Sendable {
    struct State: Equatable, Identifiable, Sendable {
        @StateModel<CounterModel> var counter = .init()
        var id: UUID
    }

    enum Event {
        case onRemove
    }

    @ModelState private var state: State

    func removeButtonTapped() {
        send(.onRemove)
    }
}

struct CounterRowView: View {
    @ObservedModel var model: CounterRowModel

    var body: some View {
        HStack {
            CounterView(model: model.$counter)

            Spacer()

            Button("Remove") {
                OneState.withAnimation {
                    model.removeButtonTapped()
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct AppModel: Model, Sendable {
    struct State: Equatable, Sendable {
        @StateModel<[CounterRowModel]> var counters = []
        @StateModel<FactPromptModel?> var factPrompt = nil

        var sum: Int {
            counters.reduce(0) { $0 + $1.counter.count }
        }
    }

    @ModelDependency(\.uuid) var uuid
    @ModelState private var state: State

    func onActivate() {
        forEach(events(of: .onRemove)) { (counter: CounterRowModel) in
            state.counters.removeAll { [id = counter.id] in $0.id == id }
        }

        forEach(events(of: .onDismiss, from: \.$factPrompt)) { _ in
            state.factPrompt = nil
        }

        forEach(events()) { (event, counter: CounterModel) in
            switch event {
            case let .onFact(fact):
                state.factPrompt = .init(count: counter.count, fact: fact)
            }
        }
    }

    func addButtonTapped() {
        state.counters.append(
            .init(counter: .init(), id: uuid())
        )
    }

    func factDismissTapped() {
        state.factPrompt = nil
    }
}

struct AppView: View {
    @ObservedModel var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            List {
                Text("Sum: \(model.sum)")

                ForEach(model.$counters) { row in
                    CounterRowView(model: row)
                }
            }
            .navigationTitle("Counters")
            .navigationBarItems(trailing: Button("Add") {
                OneState.withAnimation {
                    model.addButtonTapped()
                }
            })

            if let factPrompt = model.$factPrompt {
                FactPromptView(model: factPrompt)
            }
        }
    }
}

struct FactPromptModel: Model {
    struct State: Equatable {
        let count: Int
        var fact: String
        var isLoading = false
    }

    enum Event {
        case onDismiss
    }

    @ModelDependency(\.factClient.fetch) var fetchFact
    @ModelState private var state: State

    func getAnotherFactButtonTapped() {
        task {
            state.isLoading = true
            defer { state.isLoading = false }
            state.fact = try await fetchFact(state.count)
        } catch: { _ in }
    }

    func dismissTapped() {
        send(.onDismiss)
    }
}

struct FactPromptView: View {
    @ObservedModel var model: FactPromptModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "info.circle.fill")
                    Text("Fact")
                }
                .font(.title3.bold())

                if model.isLoading {
                    ProgressView()
                } else {
                    Text(model.fact)
                }
            }

            HStack(spacing: 12) {
                Button("Get another fact") {
                    model.getAnotherFactButtonTapped()
                }

                Button("Dismiss") {
                    model.dismissTapped()
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.1), radius: 20)
        .padding()
    }
}

struct CounterView_Previews: PreviewProvider {
    static let store = Store<AppModel>(initialState: .init())

    static var previews: some View {
        NavigationView {
            AppView(model: store.model)
        }
    }
}
