// A view into a store's state
@dynamicMemberLookup
public struct StoreView<Root, State, Access> {
    var context: Context<Root>
    private var _path: KeyPath<Root, State>
    weak var access: StoreAccess?
}

public enum Read {}
public enum Write {}

extension StoreView where Access == Read {
    init(context: Context<Root>, path: KeyPath<Root, State>, access: StoreAccess?) {
        self.context = context
        self._path = path
        self.access = access
    }
}

extension StoreView where Access == Write {
    init(context: Context<Root>, path: WritableKeyPath<Root, State>, access: StoreAccess?) {
        self.context = context
        self._path = path
        self.access = access
    }
}

extension StoreView {
    typealias Path = KeyPath<Root, State>

    var path: KeyPath<Root, State> {
        _path
    }
}

extension StoreView where Access == Write {
    typealias Path = WritableKeyPath<Root, State>

    var path: WritableKeyPath<Root, State> {
        _path as! WritableKeyPath<Root, State>
    }
}

extension StoreView: StoreViewProvider {
    public var storeView: Self { self }
}

extension StoreView: Identifiable where State: Identifiable {
    public var id: State.ID {
        context[path: path.appending(path: \.id), access: access]
    }
}

extension StoreView: Equatable where State: Equatable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.context[path: lhs.path, access: lhs.access] == rhs.context[path: rhs.path, access: lhs.access]
    }
}

extension StoreView {
    func path<T>(_ keyPath: KeyPath<State, T>) -> KeyPath<Root, T>{
        storeView.path.appending(path: keyPath)
    }
}

extension StoreView where Access == Write {
    func path<T>(_ keyPath: WritableKeyPath<State, T>) -> WritableKeyPath<Root, T>{
        storeView.path.appending(path: keyPath)
    }
}

extension StoreView: CustomStringConvertible where State: CustomStringConvertible {
    public var description: String {
        let view = storeView
        return context.value(for: view.path(\.description), access: view.access)
    }
}

@dynamicMemberLookup
public struct IdentifiableStoreView<Root, State, Access, ID: Hashable>: Identifiable, StoreViewProvider {
    public var storeView: StoreView<Root, State, Access>
    var idPath: KeyPath<State, ID>

    public var id: ID {
        storeView.context[path: storeView.path(idPath), access: storeView.access]
    }
}


