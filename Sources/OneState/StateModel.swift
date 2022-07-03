import Foundation

/// Declare what model to used to represent a models states variable
///
/// Instead of manually creating a `Model` from a `StoreView`you can instead
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
/// Given a `StoreViewProvider` such as a `Model` you can
/// get direct access to a sub model with a given state:
///
///     appModel.$main // MainModel
///     appModel.$optMain // MainModel?
///     appModel.$mains // [MainModel]
@propertyWrapper
public struct StateModel<Container: ModelContainer> {
    var _wrappedValue: Container.StateContainer

    public var wrappedValue: Container.StateContainer {
        get {
            threadState.stateModelCount += 1
            return _wrappedValue
        }
        set {
            _wrappedValue = newValue
        }
    }

    public var projectedValue: Self {
        get { self }
        set { self = newValue }
    }

    public init(wrappedValue: Container.StateContainer) {
        _wrappedValue = wrappedValue
    }
}

extension StateModel: Equatable where Container.StateContainer: Equatable {}

extension StateModel: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

public extension Model {
    @MainActor
    subscript<M: Model>(dynamicMember path: WritableKeyPath<State, StateModel<M>>) -> M where M.StateContainer == M.State {
        StoreAccess.$current.withValue(modelState?.storeAccess.map(Weak.init)) {
            M(storeView(for: path.appending(path: \.wrappedValue)))
        }
    }

    @MainActor
    subscript<Models>(dynamicMember path: WritableKeyPath<State, StateModel<Models>>) -> Models where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let view = storeView
        let containerView = StoreView(context: view.context, path: view.path(path.appending(path: \.wrappedValue)), access: view.access)
        let container = containerView.value(for: \.self, isSame: Models.StateContainer.hasSameStructure)
        let elementPaths = container.elementKeyPaths
        let models = StoreAccess.$current.withValue(modelState?.storeAccess.map(Weak.init)) {
            elementPaths.map { path in
                Models.ModelElement(containerView.storeView(for: path))
            }
        }
        return Models.modelContainer(from: models)
    }
}

public extension Model {
    /// Recieve events of from the `model`
    @discardableResult @MainActor
    func onEvent<M: Model>(from model: M, perform: @escaping @MainActor (M.Event) -> Void) -> Cancellable where M.StateContainer == M.State {
        return forEach(context.events.compactMap {
            guard let event = $0.event as? M.Event, let viewModel = $0.viewModel as? M, viewModel.context === model.context else {
                return nil
            }
            return event
        }, perform: perform)
    }

    /// Recieve events of `event`from `model´`
    @discardableResult @MainActor
    func onEvent<M: Model>(_ event: M.Event, from model: M, perform: @escaping @MainActor () -> Void) -> Cancellable where M.StateContainer == M.State, M.Event: Equatable {
        return forEach(context.events.compactMap {
            guard let aEvent = $0.event as? M.Event, aEvent == event, let viewModel = $0.viewModel as? M, viewModel.context === model.context else {
                return nil
            }
            return ()
        }, perform: perform)
    }

    /// Recieve events of from `models`
    @discardableResult @MainActor
    func onEvent<P: StoreViewProvider, Models>(from models: P, perform: @escaping @MainActor (Models.ModelElement.Event, Models.ModelElement) -> Void) -> Cancellable
    where P.State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let containerView = models.storeView(for: \.wrappedValue)

        return forEach(context.events) { anyEvent, eventPath, viewModel, callContext in
            guard let event = anyEvent as? Models.ModelElement.Event,
                  let containerPath = containerView.context.storePath.appending(path: containerView.path)
            else { return }

            let container = containerView.nonObservableState

            for path in container.elementKeyPaths {
                if let elementPath = containerPath.appending(path: path), elementPath == eventPath {
                    (callContext ?? .empty) {
                        CallContext.$current.withValue(callContext) {
                            perform(event, viewModel as! Models.ModelElement)
                        }
                    }
                }
            }
        }
    }

    /// Recieve events of `event` from `models`
    @discardableResult @MainActor
    func onEvent<P: StoreViewProvider, Models>(_ event: Models.ModelElement.Event, from view: P, perform: @escaping @MainActor (Models.ModelElement) -> Void) -> Cancellable
    where P.State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.ModelElement.Event: Equatable {
        onEvent(from: view) { aEvent, model in
            guard aEvent == event else { return }
            perform(model)
        }
    }
}

public extension Model {
    @discardableResult @MainActor
    func activate<P: StoreViewProvider, Models>(_ view: P) -> Cancellable where P.State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.StateContainer: Equatable, P.Access == Write {
        let containerView = view.storeView(for: \.wrappedValue)

        typealias ActivedModels = [WritableKeyPath<Models.StateContainer, Models.StateContainer.Element>: Models.ModelElement]
        let elementPaths = containerView.nonObservableState.elementKeyPaths
        var activatedModels = ActivedModels(uniqueKeysWithValues: elementPaths.map { key in
            let view = containerView.storeView(for: key)
            let model = Models.ModelElement(view)
            model.retain()
            return (key, model)
        })

        return task {
            for await update in containerView.stateUpdates {
                let previous = update.previous
                let current = update.current
                let isSame = Models.StateContainer.hasSameStructure(lhs: previous, rhs: current)
                guard !isSame else { continue }

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

            for model in activatedModels.values {
                model.context.releaseFromView()
            }
        }
    }
}
