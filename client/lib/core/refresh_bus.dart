/// Purpose: Coalescing refresh bus shared by the app shell and data views.
/// Data & Logic Flow: The shell requests a refresh on app resume and tab switches; subscribed views silently refetch in the background without flashing loading states.
/// Key Components: RefreshBus
import 'dart:async';

/// Broadcast channel for data-refresh requests.
///
/// Views subscribe to [stream] and refetch their data silently (keeping any
/// cached content on screen), while the shell fires [requestRefresh] on app
/// resume and tab changes. The in-flight guard inside each view coalesces
/// bursts of requests, so no extra debouncing is needed here.
class RefreshBus {
  RefreshBus._();

  static final RefreshBus instance = RefreshBus._();

  final StreamController<void> _controller = StreamController<void>.broadcast();

  /// Fires whenever the shell wants views to refresh their data.
  Stream<void> get stream => _controller.stream;

  void requestRefresh() {
    _controller.add(null);
  }
}
