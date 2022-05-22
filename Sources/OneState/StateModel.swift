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

public extension StoreViewProvider where Access == Write {
    @MainActor
    subscript<VM: ViewModel>(dynamicMember path: WritableKeyPath<State, StateModel<VM>>) -> VM where VM.StateContainer == VM.State {
        VM(storeView(for: path.appending(path: \.wrappedValue)))
    }

    @MainActor
    subscript<VM: ViewModel>(dynamicMember path: WritableKeyPath<State, Writable<StateModel<VM>>>) -> Binding<VM> where VM.StateContainer == VM.State {
        .init {
            self[dynamicMember: path.appending(path: \.wrappedValue)]
        } set: { models in
            setValue(StateModel<VM>(wrappedValue: models.stateContainer), at: path)
        }
    }

    @MainActor
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

    @MainActor
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
    /// Recieve events of from the `model`
    @discardableResult @MainActor
    func onEvent<VM: ViewModel>(from model: VM, perform: @escaping @MainActor (VM.Event) -> Void) -> AnyCancellable where VM.StateContainer == VM.State {
        return onReceive(context.eventSubject.compactMap {
            guard let event = $0.event as? VM.Event, let viewModel = $0.viewModel as? VM, viewModel.context === model.context else {
                return nil
            }
            return event
        }, perform: perform)
    }

    /// Recieve events of `event`from `model´`
    @discardableResult @MainActor
    func onEvent<VM: ViewModel>(_ event: VM.Event, from model: VM, perform: @escaping @MainActor () -> Void) -> AnyCancellable where VM.StateContainer == VM.State, VM.Event: Equatable {
        return onReceive(context.eventSubject.compactMap {
            guard let aEvent = $0.event as? VM.Event, aEvent == event, let viewModel = $0.viewModel as? VM, viewModel.context === model.context else {
                return nil
            }
            return ()
        }, perform: perform)
    }

    /// Recieve events of from `models`
    @discardableResult @MainActor
    func onEvent<P: StoreViewProvider, Models>(from models: P, perform: @escaping @MainActor (Models.ModelElement.Event, Models.ModelElement) -> Void) -> AnyCancellable
    where P.State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let containerView = models.storeView(for: \.wrappedValue)

        return onReceive(context.eventSubject) { anyEvent, eventPath, viewModel in
            guard let event = anyEvent as? Models.ModelElement.Event else { return }

            let container = containerView.nonObservableState
            for path in container.elementKeyPaths {
                let elementPath = models.storeView.path.appending(path: \.wrappedValue).appending(path: path)

                if elementPath == eventPath {
                    perform(event, viewModel as! Models.ModelElement)
                }
            }
        }
    }

    /// Recieve events of `event` from `models`
    @discardableResult @MainActor
    func onEvent<P: StoreViewProvider, Models>(_ event: Models.ModelElement.Event, from view: P, perform: @escaping @MainActor (Models.ModelElement) -> Void) -> AnyCancellable
    where P.State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.ModelElement.Event: Equatable {
        onEvent(from: view) { aEvent, model in
            guard aEvent == event else { return }
            perform(model)
        }
    }
}

public extension ViewModel {
    @discardableResult @MainActor
    func activate<P: StoreViewProvider, Models>(_ view: P) -> AnyCancellable where P.State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.StateContainer: Equatable, P.Access == Write {
        let containerView = view.storeView(for: \.wrappedValue)

        typealias ActivedModels = [WritableKeyPath<Models.StateContainer, Models.StateContainer.Element>: Models.ModelElement]
        let elementPaths = containerView.nonObservableState.elementKeyPaths
        var activatedModels = ActivedModels(uniqueKeysWithValues: elementPaths.map { key in
            let view = containerView.storeView(for: key)
            let model = Models.ModelElement(view)
            model.retain()
            return (key, model)
        })

        let publisher = containerView.stateDidUpdatePublisher
            .handleEvents(receiveCancel: {
                for model in activatedModels.values {
                    model.context.releaseFromView()
                }
            })

        return onReceive(publisher) { update in
            let previous = update.previous
            let current = update.current
            let isSame = Models.StateContainer.hasSameStructure(lhs: previous, rhs: current)
            guard !isSame else { return }

            let previousKeys = Set(previous.elementKeyPaths)
            let currentKeys = Set(current.elementKeyPaths)

            for newKey in currentKeys.subtracting(previousKeys) {
                let view = containerView.storeView(for: newKey)
                let model = Models.ModelElement(view)
                model.retain()
                activatedModels[newKey] = model
            }

            for oldKey in previousKeys.subtracting(currentKeys) {
                let model = activatedModels[oldKey]
                assert(model != nil)
                model?.context.releaseFromView()
                activatedModels[oldKey] = nil
            }
        }
    }
}
