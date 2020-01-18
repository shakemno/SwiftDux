import Combine
import SwiftUI

/// Indicates a connectable view should not update when the state changes. The view will not subscribe to the store, and instead update
/// only when it dispatches an action.
internal final class NoUpdateAction: Action {
  var unused: Bool = false
}

/// A view modifier that injects a store into the environment.
internal struct StateConnectionViewModifier<Superstate, State>: ViewModifier {
  @EnvironmentObject private var superstateConnection: StateConnection<Superstate>
  @Environment(\.storeUpdated) private var storeUpdated
  @Environment(\.actionDispatcher) private var actionDispatcher

  private var filter: ((Action) -> Bool)?
  private var mapState: (Superstate, StateBinder) -> State?

  internal init(filter: ((Action) -> Bool)?, mapState: @escaping (Superstate, StateBinder) -> State?) {
    self.filter = filter
    self.mapState = mapState
  }

  public func body(content: Content) -> some View {
    let dispatchConnection = DispatchConnection(actionDispatcher: actionDispatcher)
    let stateConnection = createStateConnection(dispatchConnection)
    return StateConnectionViewGuard(
      stateConnection: stateConnection,
      content:
        content
        .environment(\.actionDispatcher, dispatchConnection)
        .environmentObject(stateConnection)
    )
  }

  private func createStateConnection(_ dispatchConnection: DispatchConnection) -> StateConnection<State> {
    let getSuperstate = superstateConnection.getState
    let stateConnection = StateConnection<State>(
      getState: { [mapState] in
        guard let superstate = getSuperstate() else { return nil }
        return mapState(superstate, StateBinder(actionDispatcher: dispatchConnection))
      },
      changePublisher: createChangePublisher(from: dispatchConnection)
    )
    return stateConnection
  }

  private func createChangePublisher(from dispatchConnection: DispatchConnection) -> AnyPublisher<Void, Never> {
    guard let filter = filter, hasUpdateFilter() else {
      return dispatchConnection.objectWillChange.eraseToAnyPublisher()
    }
    let filterPublisher = storeUpdated.filter(filter).map { _ in }.eraseToAnyPublisher()
    return dispatchConnection.objectWillChange.merge(with: filterPublisher).eraseToAnyPublisher()
  }

  private func hasUpdateFilter() -> Bool {
    let noUpdateAction = NoUpdateAction()
    _ = filter?(noUpdateAction)
    return !noUpdateAction.unused
  }

}

/// View that renders the UI of a state connection only when state isn't nil.
private struct StateConnectionViewGuard<State, Content>: View where Content: View {

  @ObservedObject var stateConnection: StateConnection<State>
  var content: Content

  var body: some View {
    stateConnection.latestState.map { _ in content }
  }

}

extension View {

  /// Connect the application state to the UI.
  ///
  /// The returned mapped state is provided to the environment and accessible through the `MappedState` property wrapper.
  /// - Parameters
  ///   - filter: Update the state when the closure returns true. If not provided, it will only update when dispatching an action.
  ///   - mapState: Maps a superstate to a substate.
  /// - Returns: The modified view.
  @available(iOS 13.0, OSX 10.15, tvOS 13.0, watchOS 6.0, *)
  public func connect<Superstate, State>(
    updateWhen filter: ((Action) -> Bool)? = nil,
    mapState: @escaping (Superstate, StateBinder) -> State?
  ) -> some View {
    self.modifier(StateConnectionViewModifier(filter: filter, mapState: mapState))
  }

}
