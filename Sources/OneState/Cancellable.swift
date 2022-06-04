public protocol Cancellable {
    func cancel()
}

public extension Cancellable {
    /// Cancellables stored in a view model will be cancelled once the last view using the model for the
    /// same underlying state is non longer being displayed
    @discardableResult
    func store<VM: ViewModel>(in viewModel: VM) -> Cancellable {
        viewModel.context.cancellables.append(self)
        return self
    }
}

extension Task: Cancellable { }
