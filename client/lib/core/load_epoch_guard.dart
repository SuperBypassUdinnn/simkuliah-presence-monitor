/// Purpose: Epoch-based in-flight tracker preventing hung network requests from permanently locking UI refreshes.
/// Data & Logic Flow: Tracks the active request epoch and start time; force-refreshes or requests older than [timeout] advance the epoch so abandoned futures are ignored when they settle late.
/// Key Components: LoadEpochGuard
class LoadEpochGuard {
  bool _inFlight = false;
  DateTime? _startedAt;
  int _epoch = 0;

  /// Attempt to begin a load. Returns a positive epoch id if the caller
  /// should proceed, or `null` if a recent in-flight load is already running
  /// and [force] is false.
  int? tryBegin({required Duration timeout, bool force = false}) {
    final now = DateTime.now();
    final stale =
        _inFlight &&
        _startedAt != null &&
        now.difference(_startedAt!) >= timeout;
    if (_inFlight && !force && !stale) {
      return null;
    }
    _inFlight = true;
    _startedAt = now;
    return ++_epoch;
  }

  /// True if [epoch] is still the latest issued load.
  bool isCurrent(int epoch) => epoch == _epoch;

  /// Clear the in-flight marker when [epoch] is still current.
  void complete(int epoch) {
    if (epoch == _epoch) {
      _inFlight = false;
      _startedAt = null;
    }
  }
}
