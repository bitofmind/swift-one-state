import Foundation
import Combine
import SwiftUI

/// Declare what model to used to represent a models states variable
///
/// Instead of manually creating a `ViewModel` from a `StoreView`you can instead
/// set up a state with `@StateModel` to declare its type:
///
///     @StateModel<MainModel> var main = .init() // MainModel.State
///
/// This works with different kinds of contaitners as well, such as optional
/// or arrays of `Identifiable`s:
///
///     @StateModel<MainModel?> var optMain = nil // MainModel.State?
///     @StateModel<[MainModel]> var mains = [] // [MainModel.State]
///
/// Given a `StoreViewProvider` such as a `ViewModel` you can
/// get direct access to a sub model with a given state:
///
///     appModel.$main // MainModel
///     appModel.$optMain // MainModel?
///     appModel.$mains // [MainModel]
@propertyWrapper
public struct StateModel<Container: ModelContainer> {
    public var wrappedValue: Container.StateContainer

    public var projectedValue: Self {
        get { self }
        set { self = newValue }
    }

    public init(wrappedValue: Container.StateContainer) {
        self.wrappedValue = wrappedValue
    }
}

extension StateModel: Equatable where Container.StateContainer: Equatable {}

extension StateModel: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

public extension StoreViewProvider {
    subscript<VM: ViewModel>(dynamicMember path: WritableKeyPath<State, StateModel<VM>>) -> VM where VM.StateContainer == VM.State {
        VM(storeView(for: path.appending(path: \.wrappedValue)))
    }

    subscript<VM: ViewModel>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<VM>>>) -> Binding<VM> where VM.StateContainer == VM.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            setValue(StateModel<VM>(wrappedValue: models.stateContainer), at: path)
        }
    }

    subscript<Models>(dynamicMember path: WritableKeyPath<State, StateModel<Models>>) -> Models where Models.StateContainer: StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let view = storeView
        let containerView = StoreView(context: view.context, path: view.path(path.appending(path: \.wrappedValue)), access: view.access)
        let container = containerView.value(for: \.self, isSame: Models.StateContainer.hasSameStructure)
        let elementPaths = container.elementKeyPaths
        let models = elementPaths.map { path in
            Models.ModelElement(containerView.storeView(for: path))
        }
        return Models.modelContainer(from: models)
    }

    subscript<Models>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<Models>>>) -> Binding<Models> where Models.StateContainer: StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            let stateModel = StateModel<Models>(wrappedValue: models.stateContainer)
            setValue(stateModel, at: path)
        }
    }
}

public extension ViewModel {
    /// Recieve events of from the view model at `path`
    @discardableResult
    func onEvent<VM: ViewModel>(fromPath path: WritableKeyPath<State, StateModel<VM>>, perform: @escaping (VM.Event, VM) -> Void) -> AnyCancellable where VM.StateContainer == VM.State {
        let elementPath = path.appending(path: \.wrappedValue)
        return onReceive(context.eventSubject.compactMap {
            guard let event = $0.event as? VM.Event, let viewModel = $0.viewModel as? VM, $0.path == elementPath else {
                return nil
            }
            return (event, viewModel)
        }, perform: perform)
    }

    /// Recieve events of from view-models at `containerPath`
    @discardableResult
    func onEvent<Models>(fromPath containerPath: WritableKeyPath<State, StateModel<Models>>, perform: @escaping (Models.ModelElement.Event, Models.ModelElement) -> Void) -> AnyCancellable where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let view = storeView
        let containerView = StoreView(context: view.context, path: view.path(containerPath.appending(path: \.wrappedValue)), access: view.access)

        return onReceive(context.eventSubject) { anyEvent, eventPath, viewModel in
            guard let event = anyEvent as? Models.ModelElement.Event else { return }

            let container = containerView.value(for: \.self)
            for path in container.elementKeyPaths {
                let elementPath = containerPath.appending(path: \.wrappedValue).appending(path: path)

                if elementPath == eventPath {
                    perform(event, viewModel as! Models.ModelElement)
                }
            }
        }
    }
}

