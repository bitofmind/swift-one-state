import SwiftUI
import OneState
import OneStateTimeTraveler

struct RemoteModel: Model, Identifiable {
    struct State: Equatable, Identifiable {
        var info: [String: String]
        var overrideState: OverrideState? {
            didSet {
                _index = overrideState?.index ?? 0
            }
        }
        
        var _index: Int = 0
        
        var id: [String: String] { info }
        
        var count: Int {
            overrideState?.count ?? 0
        }

        var maxIndex: Int { max(0, count - 1) }
    }
    
    enum Event {
        case setOverride(Int?)
        case printDiff(Int)
    }
    
    @ModelState var state: State
    
    private(set) var index: Int {
        get { self._index }
        nonmutating set {
            if state._index != newValue {
                state._index = newValue
                send(.setOverride(newValue))
            }
        }
    }

    var canStepBackward: Bool { index > 0 }
    var canStepForward: Bool { index < self.maxIndex }
    
    func stepForwardTapped() {
        index += 1
    }
    
    func longStepForwardTapped() {
        index += 5
    }
    
    func stepBackwardTapped() {
        index -= 1
    }
    
    func longStepBackwardTapped() {
        index -= 5
    }
    
    var progressBinding: Binding<Double> {
        .init {
            Double(index)/Double(max(1, self.maxIndex))
        } set: {
            index = state.count == 0 ? 0 : Int(round($0*Double(state.maxIndex)))
        }
    }
    
    func playTapped() {
        send(.setOverride(nil))
    }
    
    func pauseTapped() {
        send(.setOverride(.max))
    }
    
    func printTapped() {
        send(.printDiff(index))
    }
}

struct RemoteView: View {
    @ObservedModel var model: RemoteModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                VStack(alignment: .leading) {
                    Text(verbatim: model.info["processName"] ?? "Unknown app")
                    Text("\(model.info["platform"] ?? "Unknown platform") - \(model.info["hostName"] ?? "Unknown host") ")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
                
                if model.overrideState != nil {
                    Button {
                        model.playTapped()
                    } label: {
                        Image(systemName: "play")
                    }
                    
                } else {
                    Button {
                        model.pauseTapped()
                    } label: {
                        Image(systemName: "pause")
                    }
                }
            }
                
            if model.overrideState != nil {
                Slider(value: model.progressBinding)

                HStack {
                    Button {
                        model.printTapped()
                    } label: {
                        Image(systemName: "printer")
                    }
                    .disabled(model.index == 0)
                    
                    Text("\(model.index + 1)/\(model.count)")

                    Spacer()
                    
                    Button {
                        model.longStepBackwardTapped()
                    } label: {
                        Image(systemName: "chevron.backward.2")
                    }
                    .disabled(!model.canStepBackward)
                    
                    Button {
                        model.stepBackwardTapped()
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!model.canStepBackward)
                    
                    Button {
                        model.stepForwardTapped()
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!model.canStepForward)
                    
                    Button {
                        model.longStepForwardTapped()
                    } label: {
                        Image(systemName: "chevron.forward.2")
                    }
                    .disabled(!model.canStepForward)
                }
            }
        }
        .padding()
    }
}
