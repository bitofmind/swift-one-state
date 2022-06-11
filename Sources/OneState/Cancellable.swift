public protocol Cancellable {
    func cancel()
}

public extension Cancellable {
    /// Cancellables stored in a model will be cancelled once the last view using the model for the
    /// same underlying state is non longer being displayed
    @discardableResult
    func store<M: Model>(in viewModel: M) -> Cancellable {
        viewModel.context.cancellables.append(self)
        return self
    }
}

extension Task: Cancellable { }
