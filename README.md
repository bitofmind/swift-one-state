# One State

One State is a library for composing models for driving SwiftUI views that comes with advanced tooling using a lightweight modern Swift style.

- [What is One State](#what-is-one-state)
- [Documentation](#documentation)
  * [Models, Stores and Composition](#models--stores-and-composition)
  * [SwiftUI Integration](#swiftui-integration)
  * [Lifetime and Asynchronous Work](#lifetime-and-asynchronous-work)
  * [Events](#events)
  * [Dependencies](#dependencies)
  * [Testing](#testing)
- [Cheat Sheet](#cheat-sheet)
- [One State Extensions](#one-state-extensions)
- [Troubleshooting](#troubleshooting)
  * [Observing of State Changes](#observing-of-state-changes)

## What is One State   

Much like SwiftUI's composition of views, One State uses well-integrated modern Swift tools for composing your app's different features into a hierarchy of models. Under the hood, One State will keep track of model state changes, sent events and ongoing asynchronous work. This result in several advantages, such as:  

- A single source of truth with tools for debugging state changes and time-traveling.
- Integrates fully with modern swift concurrency with extended tools for powerful lifetime management. 
- Natural propagation of external dependencies down the model hierarchy and sending of events up the model hierarchy.
- Exhaustive testing of state changes, events and concurrent operations.

> One State takes inspiration from similar architectures such as [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture), but aims to be less strict and esoteric by using a more familiar style.

## Documentation

Below we will build parts of a sample app that you can see as whole in the Examples folder of this repository. 

> The sample app is a straight refactoring of a [sample app](https://github.com/pointfreeco/episode-code-samples/tree/1dcb756f63536461af71f8ca8b2682dcd12e3cb4/0150-derived-behavior-pt5) that [Point-Free](https://www.pointfree.co) wrote in both plain vanilla SwiftUI and in [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) (TCA), that was used as a reference when the initial design of One State took place in the fall of 2021. Note that especially TCA has evolved a bit since that sample was written. 

### Models, Stores and Composition

Models are central building blocks in One State. A model declare a state together with operations for manipulating that state and communicating with its environment. 

You conform your models to the `Model` protocol that, at a minimum, requires your type to declare its type of `State` as well as to add a single `@ModelState` property for accessing that state. This state should have value semantics and conform to `Equatable` to ensure state changes can be detected, and for views to be updated properly.

```swift
import OneState

struct CountModel: Model {
  struct State: Equatable {
    var count = 0
  }
    
  @ModelState private var state: State
}
``` 

> The state itself is not stored by the model, instead all state is stored in a common `Store`, and a model only provides a view into that store via the `@ModelState` property.

> The `Model` protocol has an empty and default initializer, that you should never call directly. Instead model instances are always created with a view into a `Store`. However, it is seldom that you will need to do that manually, instead One State will often be able to handle this by itself if you annotate access your model's state properly. 

> Similar to SwiftUI's views, a model often will be instantiated many times for the same underlying state. Hence it does not make sense to add logic to the defaulted empty initializer, and it should typically always be left empty. Instead you will use other means for injecting dependencies and to communicate back to parent models. 

#### Accessing State

A `Model` is using dynamic member lookup for accessing its state. This allows external users, such as your views, to access a model's state-properties directly via the model itself.

```swift
let model: CountModel = ...

let count = model.count
```

State access is by design read only to promote using methods for modification. This enforces logic to be handled in the model, which improves encapsulation, maintenance and especially testing.

```swift
extension CountModel {
  func incrementTapped() {
    state.count += 1
  }
}
```

#### Store

A store holds the current state of an app's models. A typical app will only have a single store that is set up with an initial state at app launch.

```swift
let store = Store<CountModel>(initialState: .init())
let countModel = store.model
```

#### Composition with @StateModel

A model can be composed by other models where the most common composition is to have either an inline model, an optional model, or a collection of models. You embed other models by adding their state to your model's state. To make it easier to instantiate a model from one of your sub states, the frameworks provides the `@StateModel` property wrapper.

```swift
struct CounterRowModel: Model, Identifiable {
  struct State: Equatable, Identifiable {
    var id: UUID
    @StateModel<CountModel> var counter = .init()
  }

  @ModelState private var state: State
}
```

By using `@StateModel`'s projected value, a model will be instantiated with a correct view into the underlying store.

```swift
let rowModel = rowModel.$counter
rowModel.incrementTapped()
```

And given that a model (such as `CounterRowModel` above) is identifiable, you can use `@StateModel` to setup a collection of model states as well. 

```swift
struct AppModel: Model {
  struct State: Equatable {
    @StateModel<[CounterRowModel]> var counters = []
    @StateModel<FactPromptModel?> var factPrompt = nil

    var sum: Int {
      counters.reduce(0) { $0 + $1.counter.count }
    }
  }

  @ModelState private var state: State
}

for row in appModel.$counters {
  row.$counter.incrementTapped()
}
```

As your app model's state is composed of all child states, adding derived properties such as `sum` above is straight forward.

> A `@StateModel` also works with optional model state as shown above, and can be extended to work with more kinds of containers by conforming them to the `StateContainer` and `ModelContainer` protocols.

### SwiftUI Integration

One State models have been designed to integrate well with SwiftUI. Where you typically conform your models to `ObservableObject` in plain vanilla SwiftUI projects, and get access and view updates by using `@ObservedObject` in your SwiftUI views, in One State you instead conform your models to `Model` and uses `@ObservedModel` to get access and trigger view updates of your views.

```swift
struct CounterView: View {
  @ObservedModel var model: CounterModel
  
  var body: some View {
    HStack {
      Button("-") { model.decrementTapped() }
      Text("\(model.count)")
      Button("+") { model.incrementTapped() }
    }
  }
}
```

And access to embedded models and derived properties are straight forward as well.

```swift 
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

      if let factPrompt = model.$factPrompt {
        FactPromptView(model: factPrompt)
      }
    }
  }
}
```

> `@ObservedModel` has been carefully crafted to only trigger view updates when properties you are accessing from your view is updated. In comparison, `@ObservedObject` will trigger a view update no matter what `@Published` property is updated in your `ObservableObject` model object.

#### Stores

Your app's store typically lives in your SwiftUI app:

```swift
@main
struct MyApp: App {
  let store = Store<AppModel>(initialState: .init())
    
  var body: some Scene {
    WindowGroup {
      AppView(model: store.model)
    }
  }
}
```

And similarly you can create stores for your previews:

```swift
struct CounterView_Previews: PreviewProvider {
  static let store = Store<CounterModel>(
    initialState: .init(count: 4711)
  )

  static var previews: some View {
    CounterView(model: store.model)
  }
}
```


#### Bindings

As model property access is read-only by design, but many SwiftUI controls expect a `Binding`, you have a choice to either construct your binding manually and updating the state via setter methods:

```swift
Binding {
  model.count
} set: {
  model.countDidUpdate(to: $0)
}
```
 
Or explicitly allow write access by annotating your property with `@Writable`.

```swift
struct State: Equatable {
  @Writable var count = 0
}

Stepper(value: model.$count) {
  Text("\(model.count)")
}
```

#### Animations

As One State is exposing state changes and events using asynchronous streams, and they might by updated in any task context, SwiftUI's standard `withAnimation()` won't work properly out of the box. Instead your are encouraged to use implicit animations such as:

```swift
Stepper(...)
  .animation(.default, value: model.count)
```

If you really need to use explicit animations you should use One State's variant of `withAnimation()` instead:

```swift
func incrementTapped() {
  OneState.withAnimation {
    state.count += 1
  }
} 
```

#### State Change Observation

To help debugging, you can add print modifiers to your views, either to print all state changes for a model:

```swift
view.printStateUpdates(for: $model)
```

Or to only print when the view was updated due to a state change:

```swift
view.printObservedUpdates(for: $model)
```


### Lifetime and Asynchronous Work

A typical model will need to handle asynchronous work such as performing operations and listening on updates from its dependencies. It is also common to listen on child events and state changes, that One State exposes as asynchronous streams.

>  One State is fully thread safe, and supports working with your models and their state from any task context. SwiftUI helpers such as `@ObservedModel` will make sure to only update views from the `@MainActor` that is required by SwiftUI.

#### Tasks

To start some asynchronous work that is tied to the life time of your model you call `task()` on it, similarly as you would do when adding a `task()` to your view. 

```swift
extension CounterModel {
  func factButtonTapped() {
    task {
       let fact = try await fetchFact(state.count)
       send(.onFact(fact))
    } catch: { error in
      state.alert = .init(message: "Couldn't load fact.", title: "Error")
    }
  }
}  
```

#### Asynchronous Sequences

For convenience, models also provide a `forEach` helper for consuming asynchronous stream such as `changes(of:)` that will emit when the state changes, and `values(of:)` that will also begin by emitting the current value. 

```swift
func isPrime(_ value: Int) async throws -> Bool { .. }

forEach(values(of: \.count)) { count in
  state.isPrime = nil // Show spinner
  state.isPrime = try await isPrime(count)
}
```

`forEach` will by default complete its asynchronous work before handling the next value, but sometimes it is useful to cancel any previous work that might become outdated.

```swift
forEach(values(of: \.count), cancelPrevious: true) { count in
  state.isPrime = nil // Show spinner
  state.isPrime = try await isPrime(count)
}
```

#### Model Activation

The `Model` protocol provides an `onActivate()` extension point that is called by One State the first time an instance is created for a particular state of data. This is a perfect place to populate a models state from its dependencies and to set up listeners on child events and state changes:
    
```swift
func onActivate() {
  forEach(events(of: .onDismiss, from: \.$factPrompt)) { _ in
    state.factPrompt = nil
  }
}
```

#### Cancellation

All tasks started on a model are automatically cancelled once a model is deactivated (its state is removed). But `task()` and `forEach()` also returns a `Cancellable` instance that allows you to cancel an operation earlier.

```swift
let operationID = "operationID"

func startOperation() {
  task { ... }.cancel(for: operationID)
}

func stopOperation() {
  cancelAll(for: operationID)
}
```

By using a cancellation context you can group several operations to allow cancellation of them all as a group:

```swift
enum OperationID {} // A type can also work as an id

withCancellationContext(for: OperationID.self) {
  task { }
  forEach(...) { }
}
```


#### Cancel in Flight

If you perform an asynchronous operation it sometimes makes sense to cancel any already in flight operations.  

```swift
func startOperation() {
  task { ... }.cancel(for: operationID, cancelInFlight: true)
}
```

So if you call `startOperation()` while one is already ongoing, it will be cancelled and new operation is started to replace it.

If you don't need to cancel your operation from somewhere else you can let One State generate an id for you:

```swift
func startOperation() {
  task { ... }.cancelInFlight()
}
```

### Events

It is common that child models needs to communicate back to parents or ancestors. In One State this is supported by sending and receiving of events. 

```swift
enum AppEvent { 
  case logout
}

func onLogoutTapped() { // ChildModel
  send(AppEvent.logout)
}

func onActivate() { // AppModel
  forEach(events(of: AppEvent.logout)) {
    state.user = nil
  }
}
```

Events sent from a model can be received by the model itself or any of its ancestors.

Often events are specific to one type of model, and One State adds special support for `Model`'s using their `Event` expansion point.

```swift
struct CounterRowModel: Model {
  enum Event {
    case onRemove
  }

  func removeButtonTapped() {
    send(.onRemove)
  }
}
```

Now you can explicitly ask for events from composed models where your will conveniently also receive an instance of the sending model.

```swift
forEach(events(from: \.$counters)) { event, counter in
  switch event {
  case .onRemove:
    state.counters.removeAll { [id = counter.id] in
      $0.id == id 
    }
  }
}
```

And when you are interested only in a specific event, it will be enough to write:

```swift
forEach(events(of: .onDismiss, from: \.$factPrompt)) { _ in
  state.factPrompt = nil
}
```

### Dependencies

For improved control of a model's dependencies to outside systems, such as backend services, One State has a system where a model can access its dependencies without needing to know how they where configured or set up. This is very similar to how SwiftUI's environment is working.

> This has been popularized by the [swift-dependency](https://github.com/pointfreeco/swift-dependencies) package which One State integrates.

You define your dependencies similar to as you would set up a custom SwiftUI environment: 

```swift
import Dependencies 

struct FactClient {
  var fetch: @Sendable (Int) async throws -> String
}

extension DependencyValues {
  var factClient: FactClient {
    get { self[FactClientKey.self] }
    set { self[FactClientKey.self] = newValue }
  }

  private enum FactClientKey: DependencyKey {
    static let liveValue = FactClient(
      fetch: { number in
        let (data, _) = try await URLSession.shared.data(
          from: URL(string: "http://numbersapi.com/\(number)")!
        )
        return String(decoding: data, as: UTF8.self)
      }
    )
  }
}
```

And models will declare `@ModelDependency` properties to get access to its dependencies.

```swift
struct FactPromptModel: Model {
  struct State: Equatable {
    let count: Int
    var fact: String
    var isLoading = false
  }

  @ModelDependency(\.factClient.fetch) var fetchFact
  @ModelState private var state: State

  func getFactButtonTapped() {
    task {
      state.isLoading = true
      defer { state.isLoading = false }
      state.fact = try await fetchFact(state.count)
    } catch: { _ in } // ignore errors
  }
}
``` 

> In One State your are using `@ModelDependency` for your models instead of [swift-dependency](https://github.com/pointfreeco/swift-dependencies)'s `@Dependency`.

#### Overriding Dependencies

When setting up your store you can provide a trailing closure where you can override default dependencies. This is especially useful for testing and previews.

```swift
let store = Store<AppModel>(initialState: .init()) {
  $0.factClient.fetch = { "\($0) is a great number!" }
}
```

A model can override a dependency with a local value, which will affect the model itself and its descendants. An overridden value can be restored to the original value by calling `reset()`.

```swift
@ModelDependency(\.sound) var sound

func onActivate() {
  forEach(values(of: \.isSoundEnabled)) { enabled in
    if enabled {
       self.$sound.reset()
    } else {
       self.sound = .disabled
    }
  }
}
```

### Testing

As One State manages your model's state and knows when events are being sent as well if any asynchronous works is ongoing, it can help tests to be more exhaustive.

For your tests you will use a `TestStore` instead of a regular store and your models will be referenced via `@TestModel`'s similar to how `@ObservedModel` is used to access you models in SwiftUI views.

```swift
class CounterFactTests: XCTestCase {
  func testExample() async throws {
    let id = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    let store = TestStore<AppModel>(initialState: .init()) {
      $0.factClient.fetch = { "\($0) is a good number." }
      $0.uuid = .constant(id)
    }

    @TestModel var appModel = store.model
```

`@TestModel` provides test methods for asserting state changes.

```swift
    appModel.addButtonTapped()
    await $appModel.assert {
      $0.counters = [.init(counter: .init(), id: id)]
    }
```

> Assertions are required to await results, due to the asynchronous nature of state and event propagation.

You can further drill down to access child models ones they become available:

```swift
    @TestModel var counterRowModel = try XCTUnwrap(appModel.$counters.first)
    @TestModel var counterModel: CounterModel = counterRowModel.$counter

    counterModel.incrementTapped()
    await $counterModel.count.assert(1)
```

> `@TestModel` allows you to drill down the state for more succinct assertions and either assert on a value directly or  open up a closure to potentially assert several changes.

Events are asserted by checking that a model has sent them as expected:

```swift
    counterModel.factButtonTapped()
    await $counterModel.receive(.onFact("1 is a good number."))
    await $appModel.factPrompt.assert(.init(count: 1, fact: "1 is a good number."))
```

Other than checking your explicit asserts, One State will verify that nothing else in your state was changed, nor any other events was sent or that there are no asynchronous work still running related to your tested models.

To relax this exhaustive testing you can limit what areas to check (`state`, `events` and `tasks`):

```swift
store.exhaustivity = [.state, .events]
```


## Cheat Sheet

One State comes with several core types and property wrappers.

**Store**: Holds the state of an application\
**Model**: A type that models the state and logic that drives SwiftUI views.


*Part of a model:*

**@ModelState**: Declares a model's state.\
**@ModelDependency**: Declares a model dependency.\
**@ModelProperty**: Declares a value stored outside of a model's state.


*Part of a model's State:*

**@StateModel**: Declare what model to use to represent a sub-model's state.\
**@Writable**: Grant write access to part of a model's state.


*SwiftUI integration:*

**@ObservedModel**: Declares a model that will update the view on model state changes.


*Testing:*

**TestStore**: A store used for testing.\
**@TestModel**: Declares a model used for testing.


## One State Extensions

The `OneStateExtensions` library, part of the `OneState` package, provides some useful extensions to One State:

#### Identified Arrays

Point-Free's [Identified Arrays](https://github.com/pointfreeco/swift-identified-collections) makes it more convenient to work with arrays of identifiable items. This extension adds support for using `IdentifiedArray` in your `@StateModel`s.

```swift
@StateModel<IdentifiedArrayOf<CounterRowModel>> var counters = []

forEach(events(of: .onRemove, from: \.$counters)) { counter in
  state.counters.remove(id: counter.id)
}
```

#### Case Paths

Point-Free's [Case Paths](https://github.com/pointfreeco/swift-case-paths) bring the power and ergonomics of key paths to enums. This extension adds support for using case paths with `StoreView`s.

```swift
struct AppModel: Model {
  struct State: Equatable {
    var destination: Destination? = nil
  }

  enum Destination: Equatable {
    case edit(EditModel.State)
    case record(RecordModel.State)
  }
  
  @ModelState private var state: State

  var editModel: EditModel? {
    .init($state.destination.case(/Destination.edit))
  }

  var recordModel: RecordModel? {
    .init($state.destination.case(/Destination.record))
  }
}
```

## Troubleshooting

### Observing of State Changes

Observing of state changes using `@ObservedModel` requires that you access your models properties indirectly via your model (using dynamic member lookup) and not directly by accessing its state property. This allows finer control of what state access should trigger updates, to avoid unnecessary update of your views.

> It is recommended to make a model's state private to avoid external access.

A method that is being called from a view (via `@ObservedModel`), can either access the models's state directly via `state` or indirectly via self. 

For methods that is not returning a value, it is preferable to access the state directly to avoid unnecessary view updates.

```swift
func buttonTapped() {
  // Prefer, as access via self will set up a listener
  print("count \(state.count)")
}

func buttonTapped() {
  // Avoid, as access via self will set up a listener
  print("count \(self.count)")
}
```

Where as if you have computed property you should use self to access your state.

```swift
var countSquared: Int {
  // Avoid, as access via state won't set up a listener
  state.count * state.count
}

var countSquared: Int {
  // Prefer, as access via self will set up a listener
  self.count * self.count
}
```

Of course it is often preferable to add computed properties directly to your `State` when that is possible.

```swift
struct State: Equatable {
  var count: Int
  var countSquared: Int { count * count }
} 
```


