import Foundation
import CustomDump

/// Declare what model to used to represent a models states variable
///
/// Instead of manually creating a `Model` from a `StoreView`you can instead
/// set up a state with `@StateModel` to declare its type:
///
///     @StateModel<MainModel> var main = .init() // MainModel.State
///
/// This works with different kinds of containers as well, such as optional
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
            ThreadState.current.stateModelCount += 1
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

extension StateModel: Sendable where Container.StateContainer: Sendable {}

extension StateModel: Equatable where Container.StateContainer: Equatable {}

extension StateModel: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

public extension Model {
    subscript<M: Model>(dynamicMember path: WritableKeyPath<State, StateModel<M>>) -> M where M.StateContainer == M.State {
        StoreAccess.$current.withValue(modelState?.storeAccess.map(Weak.init)) {
            M(storeView(for: path.appending(path: \.wrappedValue)))
        }
    }

    subscript<Models>(dynamicMember path: WritableKeyPath<State, StateModel<Models>>) -> Models where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        let view = storeView
        let containerPath = path.appending(path: \.wrappedValue)
        let containerView = StoreView(context: view.context, path: containerPath, access: view.access)
        let container = view.context.value(for: containerView.path, access: containerView.access, comparable: StructureComparableValue.self)
        let elementPaths = container.elementKeyPaths
        let models = StoreAccess.$current.withValue(modelState?.storeAccess.map(Weak.init)) {
            elementPaths.map { path in
                Models.ModelElement(containerView.storeView(for: path))
            }
        }

        view.observeContainer(atPath: path)

        return Models.modelContainer(from: models)
    }
}

public extension StoreViewProvider  {
    func events<Models: ModelContainer>() -> CallContextsStream<(event: Models.ModelElement.Event, model: Models.ModelElement)> where State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.ModelElement.Event: Sendable {
        let containerView = storeView(for: \.wrappedValue)
        let events = storeView.context.events

        return CallContextsStream(events.compactMap { e -> WithCallContexts<(event: Models.ModelElement.Event, model: Models.ModelElement)>? in
            guard let event = e.event as? Models.ModelElement.Event,
                  let containerPath = containerView.context.storePath.appending(path: containerView.path)
            else { return nil }

            let container = containerView.nonObservableState

            for path in container.elementKeyPaths {
                if let elementPath = containerPath.appending(path: path), elementPath == e.path {
                    let context = e.context as! Context<Models.ModelElement.State>
                    return WithCallContexts(value: (event, Models.ModelElement(context: context)), callContexts: e.callContexts)
                }
            }

            return nil
        })
    }

    func events<Models: ModelContainer>(of event: Models.ModelElement.Event) -> CallContextsStream<Models.ModelElement> where State == StateModel<Models>, Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.ModelElement.Event: Sendable&Equatable  {
        let events = events()
        return CallContextsStream(events.stream.compactMap {
            $0.value.event == event ? .init(value: $0.value.model, callContexts: $0.callContexts) : nil
        })
    }

    func events<M: Model>() -> CallContextsStream<M.Event> where State == StateModel<M>, M.StateContainer == M.State, Access == Write {
        let events = M(storeView(for: \.wrappedValue)).context.events

        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? M.Event else { return nil }
            return .init(value: e, callContexts: $0.callContexts)
        })
    }

    func events<M: Model>(of event: M.Event) -> CallContextsStream<()> where State == StateModel<M>, M.StateContainer == M.State, Access == Write, M.Event: Equatable&Sendable {
        let events = M(storeView(for: \.wrappedValue)).context.events

        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? M.Event, e == event else { return nil }
            return .init(value: (), callContexts: $0.callContexts)
        })
    }
}

extension StateModel: CustomDumpRepresentable {
    public var customDumpValue: Any {
        wrappedValue
    }
}
