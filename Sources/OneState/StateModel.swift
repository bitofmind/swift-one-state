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

    public init(_ container: Container.StateContainer) {
        _wrappedValue = container
    }
}

extension StateModel: Sendable where Container.StateContainer: Sendable {}

extension StateModel: Equatable where Container.StateContainer: Equatable {}

extension StateModel: CustomStringConvertible {
    public var description: String {
        String(describing: wrappedValue)
    }
}

extension StateModel: CustomDumpRepresentable {
    public var customDumpValue: Any {
        wrappedValue
    }
}

public extension Model {
    subscript<M: Model>(dynamicMember path: WritableKeyPath<State, StateModel<M>>) -> M where M.StateContainer == M.State {
        StoreAccess.with(modelState?.storeAccess) {
            M(storeView(for: path.appending(path: \.wrappedValue)))
        }
    }

    subscript<Models>(dynamicMember path: WritableKeyPath<State, StateModel<Models>>) -> Models where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        Models(storeView.storeView(for: path))
    }
}

public extension StoreViewProvider where Access == Write {
    subscript<Models>(dynamicMember path: WritableKeyPath<State, StateModel<Models>>) -> StoreView<Root, StateModel<Models>, Write> where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State {
        observeContainer(atPath: path)
        return storeView(for: path)
    }

    subscript<S, T>(dynamicMember path: WritableKeyPath<S, T>) -> StoreView<Root, T?, Write> where State == S? {
        let view = storeView
        let unwrapPath = view.path.appending(path: \.[unwrap: path])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }

    subscript<S, T>(dynamicMember path: WritableKeyPath<S, T?>) -> StoreView<Root, T?, Write> where State == S? {
        let view = storeView
        let unwrapPath = view.path.appending(path: \.[unwrap: path])
        return StoreView(context: view.context, path: unwrapPath, access: view.access)
    }
}

public extension Model {
    func events<Models: ModelContainer>(from path: WritableKeyPath<State, StateModel<Models>>) -> CallContextsStream<(event: Models.ModelElement.Event, model: Models.ModelElement)> where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.ModelElement.Event: Sendable {
        let containerView = storeView(for: path).wrappedValue
        containerView.observeContainer(ofType: Models.self, atPath: \.self)
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

    func events<Models: ModelContainer>(of event: Models.ModelElement.Event, from path: WritableKeyPath<State, StateModel<Models>>) -> CallContextsStream<Models.ModelElement> where Models.StateContainer: OneState.StateContainer, Models.StateContainer.Element == Models.ModelElement.State, Models.ModelElement.Event: Sendable&Equatable {
        CallContextsStream(events(from: path).stream.compactMap {
            $0.value.event == event ? .init(value: $0.value.model, callContexts: $0.callContexts) : nil
        })
    }

    func events<M: Model>(from path: WritableKeyPath<State, StateModel<M>>) -> CallContextsStream<M.Event> where M.StateContainer == M.State {
        let events = M(storeView(for: path).wrappedValue).context.events

        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? M.Event else { return nil }
            return .init(value: e, callContexts: $0.callContexts)
        })
    }

    func events<M: Model>(of event: M.Event, from path: WritableKeyPath<State, StateModel<M>>) -> CallContextsStream<()> where M.StateContainer == M.State, M.Event: Equatable&Sendable {
        let events = M(storeView(for: path).wrappedValue).context.events

        return CallContextsStream(events.compactMap {
            guard let e = $0.event as? M.Event, e == event else { return nil }
            return .init(value: (), callContexts: $0.callContexts)
        })
    }
}

